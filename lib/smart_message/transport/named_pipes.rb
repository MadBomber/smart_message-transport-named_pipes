# frozen_string_literal: true

require_relative "named_pipes/version"
require 'smart_message/transport/base'
require 'fileutils'

module SmartMessage
  module Transport
    class NamedPipes < Base
      class Error < StandardError; end
      
      DEFAULT_CONFIG = {
        base_path: ENV['SMART_MESSAGE_PIPE_BASE'] || '/tmp/smart_message/pipes',
        namespace: ENV['SMART_MESSAGE_NAMESPACE'] || 'default',
        mode: :unidirectional,      # Recommended for avoiding deadlocks
        permissions: 0600,           # Owner read/write only
        cleanup: true,              # Delete pipes on shutdown
        buffer_size: 65536,         # 64KB default buffer
        timeout: 5.0                # 5 second timeout for pipe operations
      }.freeze

      attr_reader :pipe_path, :subscriber_pipes, :publisher_pipes

      def initialize(**options)
        super(**options)
        @subscriber_pipes = {}
        @publisher_pipes = {}
        @pipe_readers = {}
        @shutdown = false
        
        setup_signal_handlers
        at_exit { cleanup_pipes }
      end

      def configure
        @pipe_path = File.join(@options[:base_path], @options[:namespace])
        FileUtils.mkdir_p(@pipe_path, mode: 0755)
        logger.debug { "[NamedPipes] Configured with pipe path: #{@pipe_path}" }
      end

      def default_options
        DEFAULT_CONFIG
      end

      def do_publish(message_class, serialized_message)
        channel_name = derive_channel_name(message_class)
        pipe_name = subscriber_pipe_name(channel_name)
        
        unless File.exist?(pipe_name)
          logger.debug { "[NamedPipes] No subscriber pipe found for #{channel_name}, message dropped" }
          return
        end

        write_to_pipe(pipe_name, serialized_message)
        logger.debug { "[NamedPipes] Published message to #{channel_name}" }
      end

      def subscribe(message_class, process_method, filter_options = {})
        super(message_class, process_method, filter_options)
        
        channel_name = derive_channel_name(message_class)
        create_subscriber_pipe(channel_name)
        start_pipe_reader(channel_name, message_class) unless @pipe_readers[channel_name]
      end

      def unsubscribe(message_class, process_method)
        super(message_class, process_method)
        
        channel_name = derive_channel_name(message_class)
        # Only remove pipe if no more subscribers for this message class
        if @dispatcher.subscribers[message_class].empty?
          stop_pipe_reader(channel_name)
          remove_subscriber_pipe(channel_name)
        end
      end

      def connected?
        !@shutdown && File.directory?(@pipe_path)
      end

      def connect
        configure unless @pipe_path
        logger.info { "[NamedPipes] Transport connected" }
      end

      def disconnect
        @shutdown = true
        cleanup_pipes
        logger.info { "[NamedPipes] Transport disconnected" }
      end

      private

      def derive_channel_name(message_class)
        message_class.to_s.gsub('::', '_').downcase
      end

      def subscriber_pipe_name(channel_name)
        File.join(@pipe_path, "#{channel_name}.in.pipe")
      end

      def publisher_pipe_name(channel_name)
        File.join(@pipe_path, "#{channel_name}.out.pipe")
      end

      def create_subscriber_pipe(channel_name)
        pipe_name = subscriber_pipe_name(channel_name)
        return if File.exist?(pipe_name)

        begin
          system("mkfifo", pipe_name)
          File.chmod(@options[:permissions], pipe_name)
          @subscriber_pipes[channel_name] = pipe_name
          logger.debug { "[NamedPipes] Created subscriber pipe: #{pipe_name}" }
        rescue => e
          logger.error { "[NamedPipes] Failed to create pipe #{pipe_name}: #{e.message}" }
          raise Error, "Failed to create named pipe: #{e.message}"
        end
      end

      def remove_subscriber_pipe(channel_name)
        pipe_name = @subscriber_pipes.delete(channel_name)
        if pipe_name && File.exist?(pipe_name)
          File.unlink(pipe_name)
          logger.debug { "[NamedPipes] Removed subscriber pipe: #{pipe_name}" }
        end
      end

      def start_pipe_reader(channel_name, message_class)
        pipe_name = subscriber_pipe_name(channel_name)
        
        @pipe_readers[channel_name] = Thread.new do
          Thread.current.name = "NamedPipes-#{channel_name}"
          
          begin
            while !@shutdown
              # Open pipe in non-blocking mode to avoid hanging
              begin
                File.open(pipe_name, 'r') do |pipe|
                  while !@shutdown && !pipe.eof?
                    if IO.select([pipe], nil, nil, 0.1) # 100ms timeout
                      data = pipe.gets
                      if data && !data.strip.empty?
                        receive(message_class.to_s, data.strip)
                      end
                    end
                  end
                end
              rescue Errno::ENXIO
                # No writers, sleep and retry
                sleep(0.1)
              rescue => e
                logger.error { "[NamedPipes] Error reading from pipe #{pipe_name}: #{e.message}" }
                sleep(1)
              end
            end
          rescue => e
            logger.error { "[NamedPipes] Pipe reader thread error for #{channel_name}: #{e.message}" }
          ensure
            logger.debug { "[NamedPipes] Pipe reader thread terminated for #{channel_name}" }
          end
        end
      end

      def stop_pipe_reader(channel_name)
        reader_thread = @pipe_readers.delete(channel_name)
        if reader_thread && reader_thread.alive?
          reader_thread.kill
          reader_thread.join(1.0) # Wait up to 1 second
        end
      end

      def write_to_pipe(pipe_name, data)
        begin
          # Use timeout to prevent hanging on blocked pipes
          Timeout.timeout(@options[:timeout]) do
            File.open(pipe_name, 'w') do |pipe|
              pipe.puts(data)
              pipe.flush
            end
          end
        rescue Errno::EPIPE
          logger.warn { "[NamedPipes] Broken pipe when writing to #{pipe_name}" }
        rescue Timeout::Error
          logger.error { "[NamedPipes] Timeout writing to pipe #{pipe_name}" }
          raise Error, "Timeout writing to named pipe"
        rescue => e
          logger.error { "[NamedPipes] Error writing to pipe #{pipe_name}: #{e.message}" }
          raise Error, "Failed to write to named pipe: #{e.message}"
        end
      end

      def cleanup_pipes
        return unless @options[:cleanup]
        
        # Stop all reader threads
        @pipe_readers.keys.each { |channel_name| stop_pipe_reader(channel_name) }
        
        # Remove all subscriber pipes
        @subscriber_pipes.values.each do |pipe_name|
          File.unlink(pipe_name) if File.exist?(pipe_name)
        end
        
        @subscriber_pipes.clear
        @publisher_pipes.clear
        
        # Remove pipe directory if empty
        begin
          Dir.rmdir(@pipe_path) if @pipe_path && File.directory?(@pipe_path) && Dir.empty?(@pipe_path)
        rescue => e
          logger.debug { "[NamedPipes] Could not remove pipe directory: #{e.message}" }
        end
        
        logger.debug { "[NamedPipes] Pipe cleanup completed" }
      end

      def setup_signal_handlers
        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            @shutdown = true
            cleanup_pipes
            exit(0)
          end
        end
      end
    end
  end
end

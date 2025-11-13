# frozen_string_literal: true

require 'smart_message/transport/base'
require 'fileutils'
require 'timeout'

module SmartMessage
  module Transport
    # Unix named pipes (FIFO) transport for SmartMessage.
    #
    # This transport enables fast inter-process communication between processes
    # running on the same machine using Unix named pipes.
    #
    # @example Basic usage
    #   transport = SmartMessage::Transport::NamedPipes.new(
    #     base_path: '/tmp/my_app/pipes',
    #     namespace: 'production',
    #     timeout: 5.0
    #   )
    #   transport.connect
    #   transport.subscribe(MyMessage, method(:handle_message))
    #   transport.publish(MyMessage, my_message)
    #   transport.disconnect
    #
    # @note This transport only works on Unix-like operating systems (Linux, macOS, BSD).
    #   Windows is not supported.
    #
    # @see https://github.com/MadBomber/smart_message-transport-named_pipes
    class NamedPipes < Base
      VERSION = "0.0.1"

      # Custom error class for NamedPipes transport errors
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

      # @return [String] the directory path where pipes are stored
      attr_reader :pipe_path

      # @return [Hash<String, String>] map of channel names to subscriber pipe paths
      attr_reader :subscriber_pipes

      # @return [Hash<String, String>] map of channel names to publisher pipe paths
      attr_reader :publisher_pipes

      # Initialize a new NamedPipes transport.
      #
      # @param options [Hash] configuration options
      # @option options [String] :base_path ('/tmp/smart_message/pipes') root directory for pipes
      # @option options [String] :namespace ('default') namespace for isolating applications
      # @option options [Symbol] :mode (:unidirectional) pipe mode
      # @option options [Integer] :permissions (0600) Unix file permissions for pipes
      # @option options [Boolean] :cleanup (true) automatically remove pipes on shutdown
      # @option options [Integer] :buffer_size (65536) buffer size in bytes
      # @option options [Float] :timeout (5.0) timeout in seconds for write operations
      #
      # @example
      #   transport = SmartMessage::Transport::NamedPipes.new(
      #     base_path: '/var/run/my_app',
      #     namespace: 'production',
      #     permissions: 0660,
      #     timeout: 3.0
      #   )
      def initialize(**options)
        super(**options)
        @subscriber_pipes = {}
        @publisher_pipes = {}
        @pipe_readers = {}
        @shutdown = false
        @mutex = Mutex.new

        setup_signal_handlers
        at_exit { cleanup_pipes }
      end

      # Configure the transport by creating the pipe directory.
      #
      # This method is called automatically by {#connect} if not already configured.
      #
      # @return [void]
      def configure
        @pipe_path = File.join(@options[:base_path], @options[:namespace])
        FileUtils.mkdir_p(@pipe_path, mode: 0755)
        logger.debug { "[NamedPipes] Configured with pipe path: #{@pipe_path}" }
      end

      # Return default configuration options.
      #
      # @return [Hash] default options from DEFAULT_CONFIG
      def default_options
        DEFAULT_CONFIG
      end

      # Publish a message to the transport.
      #
      # @param message_class [Class] the message class
      # @param serialized_message [String] the serialized message data
      # @return [void]
      # @raise [Error] if writing to the pipe fails
      def do_publish(message_class, serialized_message)
        channel_name = derive_channel_name(message_class)
        pipe_name = subscriber_pipe_name(channel_name)

        unless File.exist?(pipe_name)
          logger.debug { "[NamedPipes] No subscriber pipe found for #{channel_name} at #{pipe_name}, message dropped" }
          return
        end

        write_to_pipe(pipe_name, serialized_message)
        logger.debug { "[NamedPipes] Published #{serialized_message.bytesize} bytes to #{channel_name}" }
      rescue Error => e
        logger.error { "[NamedPipes] Failed to publish to #{channel_name}: #{e.message}" }
        raise
      end

      # Subscribe to messages of a specific class.
      #
      # Creates a named pipe for the message class if it doesn't exist, and starts
      # a background thread to read from the pipe.
      #
      # @param message_class [Class] the message class to subscribe to
      # @param process_method [Method, Proc] the method/proc to call when a message is received
      # @param filter_options [Hash] optional filter options (passed to parent)
      # @return [void]
      def subscribe(message_class, process_method, filter_options = {})
        super(message_class, process_method, filter_options)

        channel_name = derive_channel_name(message_class)
        create_subscriber_pipe(channel_name)

        # Thread-safe check to avoid starting duplicate readers
        needs_reader = @mutex.synchronize { !@pipe_readers.key?(channel_name) }
        start_pipe_reader(channel_name, message_class) if needs_reader
      end

      # Unsubscribe from messages of a specific class.
      #
      # Stops the reader thread and removes the pipe if no more subscribers exist
      # for this message class.
      #
      # @param message_class [Class] the message class to unsubscribe from
      # @param process_method [Method, Proc] the method/proc to remove
      # @return [void]
      def unsubscribe(message_class, process_method)
        super(message_class, process_method)
        
        channel_name = derive_channel_name(message_class)
        # Only remove pipe if no more subscribers for this message class
        if @dispatcher.subscribers[message_class].empty?
          stop_pipe_reader(channel_name)
          remove_subscriber_pipe(channel_name)
        end
      end

      # Check if the transport is currently connected.
      #
      # @return [Boolean] true if connected and not shut down
      def connected?
        !@shutdown && File.directory?(@pipe_path)
      end

      # Connect the transport.
      #
      # Configures the pipe directory if not already done.
      #
      # @return [void]
      def connect
        configure unless @pipe_path
        logger.info { "[NamedPipes] Transport connected" }
      end

      # Disconnect the transport.
      #
      # Sets the shutdown flag, notifies reader threads, and cleans up resources.
      #
      # @return [void]
      def disconnect
        @shutdown = true

        # Wake up all sleeping threads by signaling shutdown
        notify_shutdown

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
          @mutex.synchronize { @subscriber_pipes[channel_name] = pipe_name }
          logger.debug { "[NamedPipes] Created subscriber pipe: #{pipe_name}" }
        rescue => e
          logger.error { "[NamedPipes] Failed to create pipe #{pipe_name}: #{e.message}" }
          raise Error, "Failed to create named pipe: #{e.message}"
        end
      end

      def remove_subscriber_pipe(channel_name)
        pipe_name = @mutex.synchronize { @subscriber_pipes.delete(channel_name) }
        if pipe_name && File.exist?(pipe_name)
          File.unlink(pipe_name)
          logger.debug { "[NamedPipes] Removed subscriber pipe: #{pipe_name}" }
        end
      end

      def start_pipe_reader(channel_name, message_class)
        pipe_name = subscriber_pipe_name(channel_name)

        reader_thread = Thread.new do
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
                        logger.debug { "[NamedPipes] Received #{data.bytesize} bytes on #{channel_name}" }
                        receive(message_class.to_s, data.strip)
                      end
                    end
                  end
                end
              rescue Errno::ENXIO => e
                # No writers yet, sleep and retry
                logger.debug { "[NamedPipes] Waiting for writer on #{pipe_name}" } if rand < 0.01 # Log occasionally
                sleep(0.1)
              rescue IOError => e
                logger.warn { "[NamedPipes] IO error reading from pipe #{pipe_name}: #{e.message}" }
                sleep(0.5)
              rescue SystemCallError => e
                logger.error { "[NamedPipes] System error reading from pipe #{pipe_name}: #{e.class} - #{e.message}" }
                sleep(1)
              rescue => e
                logger.error { "[NamedPipes] Unexpected error reading from pipe #{pipe_name}: #{e.class} - #{e.message}\n#{e.backtrace.first(3).join("\n")}" }
                sleep(1)
              end
            end
          rescue => e
            logger.error { "[NamedPipes] Pipe reader thread error for #{channel_name}: #{e.message}" }
          ensure
            logger.debug { "[NamedPipes] Pipe reader thread terminated for #{channel_name}" }
          end
        end

        @mutex.synchronize { @pipe_readers[channel_name] = reader_thread }
      end

      def stop_pipe_reader(channel_name)
        reader_thread = @mutex.synchronize { @pipe_readers.delete(channel_name) }
        if reader_thread && reader_thread.alive?
          # Signal shutdown and wait for thread to exit gracefully
          # Thread will exit on next @shutdown check in loop
          reader_thread.join(2.0) # Wait up to 2 seconds
          # If still alive, force termination
          reader_thread.kill if reader_thread.alive?
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
        rescue Errno::EPIPE => e
          logger.warn { "[NamedPipes] Broken pipe when writing to #{pipe_name}: reader likely disconnected" }
          # Don't raise - this is expected when reader closes
        rescue Timeout::Error
          logger.error { "[NamedPipes] Timeout (#{@options[:timeout]}s) writing to pipe #{pipe_name}: no reader consuming data" }
          raise Error, "Timeout writing to named pipe after #{@options[:timeout]} seconds"
        rescue Errno::ENXIO => e
          logger.warn { "[NamedPipes] No reader for pipe #{pipe_name}" }
          # Don't raise - pipe exists but no reader yet
        rescue SystemCallError => e
          logger.error { "[NamedPipes] System error writing to pipe #{pipe_name}: #{e.class} - #{e.message}" }
          raise Error, "System error writing to named pipe: #{e.class} - #{e.message}"
        rescue => e
          logger.error { "[NamedPipes] Unexpected error writing to pipe #{pipe_name}: #{e.class} - #{e.message}\n#{e.backtrace.first(3).join("\n")}" }
          raise Error, "Failed to write to named pipe: #{e.message}"
        end
      end

      def cleanup_pipes
        return unless @options[:cleanup]

        # Stop all reader threads
        channel_names = @mutex.synchronize { @pipe_readers.keys.dup }
        channel_names.each { |channel_name| stop_pipe_reader(channel_name) }

        # Remove all subscriber pipes
        pipes_to_remove = @mutex.synchronize { @subscriber_pipes.values.dup }
        pipes_to_remove.each do |pipe_name|
          begin
            File.unlink(pipe_name) if File.exist?(pipe_name)
          rescue Errno::ENOENT
            # File was already deleted (possibly by concurrent cleanup)
            logger.debug { "[NamedPipes] Pipe #{pipe_name} already removed" }
          end
        end

        @mutex.synchronize do
          @subscriber_pipes.clear
          @publisher_pipes.clear
        end
        
        # Remove pipe directory if empty
        begin
          Dir.rmdir(@pipe_path) if @pipe_path && File.directory?(@pipe_path) && Dir.empty?(@pipe_path)
        rescue => e
          logger.debug { "[NamedPipes] Could not remove pipe directory: #{e.message}" }
        end
        
        logger.debug { "[NamedPipes] Pipe cleanup completed" }
      end

      def notify_shutdown
        # Notify all reader threads to wake up and check shutdown flag
        threads = @mutex.synchronize { @pipe_readers.values.dup }
        threads.each { |thread| thread.wakeup if thread.alive? rescue nil }
      end

      def setup_signal_handlers
        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            @shutdown = true
            notify_shutdown
            cleanup_pipes
            exit(0)
          end
        end
      end
    end
  end
end

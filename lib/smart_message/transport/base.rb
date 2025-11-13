# frozen_string_literal: true
# Stub file for testing - will be replaced by actual smart_message gem

module SmartMessage
  module Transport
    class Base
      attr_reader :options, :dispatcher

      def initialize(**options)
        @options = default_options.merge(options)
        @dispatcher = Dispatcher.new
        configure if respond_to?(:configure)
      end

      def default_options
        {}
      end

      def logger
        @logger ||= Logger.new
      end

      def subscribe(message_class, process_method, filter_options = {})
        # To be implemented by transport
      end

      def unsubscribe(message_class, process_method)
        # To be implemented by transport
      end

      def receive(message_class_name, serialized_data)
        # To be implemented - would deserialize and dispatch
      end

      def publish(message_class, message_data)
        # To be implemented by transport
      end

      def connect
        # To be implemented by transport
      end

      def disconnect
        # To be implemented by transport
      end

      def connected?
        # To be implemented by transport
      end

      class Dispatcher
        attr_reader :subscribers

        def initialize
          @subscribers = Hash.new { |h, k| h[k] = [] }
        end
      end

      class Logger
        def debug(&block); end
        def info(&block); end
        def warn(&block); end
        def error(&block); end
      end
    end
  end
end

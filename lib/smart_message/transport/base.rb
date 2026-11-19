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
        @dispatcher.add(message_class, process_method, filter_options)
      end

      def unsubscribe(message_class, process_method)
        @dispatcher.drop(message_class, process_method)
      end

      def unsubscribe!(message_class)
        @dispatcher.drop_all(message_class)
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

      # Keys subscribers by String(message_class), as smart_message's Dispatcher does.
      class Dispatcher
        attr_reader :subscribers

        def initialize
          @subscribers = Hash.new { |h, k| h[k] = [] }
        end

        def add(message_class, process_method, _filter_options = {})
          @subscribers[String(message_class)] << process_method
        end

        def drop(message_class, process_method)
          @subscribers[String(message_class)].delete(process_method)
        end

        def drop_all(message_class)
          @subscribers.delete(String(message_class))
        end
      end

      # Evaluates each message block, as smart_message's real logger does, so
      # an error inside a log message fails the suite instead of production.
      class Logger
        %i[debug info warn error].each do |level|
          define_method(level) do |&block|
            block&.call
            nil
          end
        end
      end
    end
  end
end

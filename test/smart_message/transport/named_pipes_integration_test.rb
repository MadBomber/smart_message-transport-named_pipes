# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class SmartMessage::Transport::NamedPipesIntegrationTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("named_pipes_integration")
    @options = {
      base_path: @test_dir,
      namespace: "integration_test",
      cleanup: true,
      timeout: 2.0,
      permissions: 0600
    }
  end

  def teardown
    @transport&.disconnect
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
  end

  # Assigned to @transport so teardown disconnects it.
  def new_transport
    @transport = SmartMessage::Transport::NamedPipes.new(**@options)
  end

  def test_write_to_pipe_simple_message
    transport = new_transport
    transport.configure

    channel_name = "test_channel"
    pipe_name = transport.send(:subscriber_pipe_name, channel_name)

    # Create the pipe
    transport.send(:create_subscriber_pipe, channel_name)

    # Start a reader thread
    received_data = nil
    reader_thread = Thread.new do
      File.open(pipe_name, 'r') do |pipe|
        received_data = pipe.gets
      end
    end

    # Give reader time to open the pipe
    sleep 0.1

    # Write to the pipe
    test_message = "Hello, Named Pipes!"
    transport.send(:write_to_pipe, pipe_name, test_message)

    # Wait for reader to finish
    reader_thread.join(1.0)

    assert_equal "#{test_message}\n", received_data
  end

  def test_pipe_communication_multiple_messages
    transport = new_transport
    transport.configure

    channel_name = "multi_message_channel"
    pipe_name = transport.send(:subscriber_pipe_name, channel_name)

    # Create the pipe
    transport.send(:create_subscriber_pipe, channel_name)

    # Start a reader thread that reads multiple messages. Open read-write, as
    # the transport's own reader does: write_to_pipe opens and closes the FIFO
    # per message, so a read-only reader would hit EOF after the first one.
    received_messages = []
    reader_thread = Thread.new do
      File.open(pipe_name, 'r+') do |pipe|
        3.times do
          if data = pipe.gets
            received_messages << data.strip
          end
        end
      end
    end

    # Give reader time to open the pipe
    sleep 0.1

    # Write multiple messages
    messages = ["Message 1", "Message 2", "Message 3"]
    messages.each do |msg|
      transport.send(:write_to_pipe, pipe_name, msg)
    end

    # Wait for reader to finish
    reader_thread.join(2.0)

    assert_equal messages, received_messages
  ensure
    reader_thread&.kill
  end

  def test_thread_safety_concurrent_pipe_operations
    transport = new_transport
    transport.configure

    # Create multiple pipes concurrently
    threads = 10.times.map do |i|
      Thread.new do
        channel_name = "concurrent_channel_#{i}"
        transport.send(:create_subscriber_pipe, channel_name)
      end
    end

    threads.each(&:join)

    # Verify all pipes were created
    10.times do |i|
      channel_name = "concurrent_channel_#{i}"
      pipe_name = transport.send(:subscriber_pipe_name, channel_name)
      assert File.exist?(pipe_name), "Pipe #{pipe_name} should exist"
    end
  end

  def test_connect_and_disconnect
    transport = new_transport

    # Initially not configured (no pipe_path set)
    # Note: connected? checks @shutdown flag and pipe_path existence

    # Connect
    transport.connect
    assert transport.connected?

    # Disconnect sets @shutdown flag
    transport.disconnect

    # After disconnect, @shutdown is true so connected? returns false
    refute transport.connected?
  end

  def test_multiple_transports_same_namespace
    # This tests that multiple transport instances can coexist
    transport1 = SmartMessage::Transport::NamedPipes.new(**@options)
    transport2 = SmartMessage::Transport::NamedPipes.new(**@options)

    transport1.configure
    transport2.configure

    # Both should see the same pipe path
    assert_equal transport1.pipe_path, transport2.pipe_path

    # Create a pipe with transport1
    channel_name = "shared_channel"
    transport1.send(:create_subscriber_pipe, channel_name)

    pipe_name = transport1.send(:subscriber_pipe_name, channel_name)

    # transport2 should see the same pipe
    assert File.exist?(pipe_name)

    transport1.disconnect

    assert transport2.connected?, "another transport's disconnect removed the shared directory"
    transport2.subscribe("SharedMessage", ->(*) {})
    assert File.pipe?(transport2.send(:subscriber_pipe_name, "sharedmessage"))
  ensure
    transport1&.disconnect
    transport2&.disconnect
  end

  def test_subscribe_recreates_a_removed_namespace_directory
    transport = new_transport
    transport.connect
    Dir.rmdir(transport.pipe_path)

    transport.subscribe("LateMessage", ->(*) {})

    assert File.pipe?(transport.send(:subscriber_pipe_name, "latemessage"))
  end
end

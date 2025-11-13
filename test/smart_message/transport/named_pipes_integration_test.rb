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

  def test_write_to_pipe_simple_message
    skip "Integration test requires full SmartMessage framework"

    transport = SmartMessage::Transport::NamedPipes.new(**@options)
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
    skip "Integration test requires full SmartMessage framework"

    transport = SmartMessage::Transport::NamedPipes.new(**@options)
    transport.configure

    channel_name = "multi_message_channel"
    pipe_name = transport.send(:subscriber_pipe_name, channel_name)

    # Create the pipe
    transport.send(:create_subscriber_pipe, channel_name)

    # Start a reader thread that reads multiple messages
    received_messages = []
    reader_thread = Thread.new do
      File.open(pipe_name, 'r') do |pipe|
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
  end

  def test_pipe_timeout_when_no_reader
    transport = SmartMessage::Transport::NamedPipes.new(**@options)
    transport.configure

    channel_name = "timeout_test"
    pipe_name = transport.send(:subscriber_pipe_name, channel_name)

    # Create the pipe but don't start a reader
    transport.send(:create_subscriber_pipe, channel_name)

    # Writing should timeout (not hang forever)
    error = assert_raises(SmartMessage::Transport::NamedPipes::Error) do
      transport.send(:write_to_pipe, pipe_name, "This should timeout")
    end

    assert_match(/Timeout writing to named pipe/, error.message)
  end

  def test_thread_safety_concurrent_pipe_operations
    transport = SmartMessage::Transport::NamedPipes.new(**@options)
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

  def test_cleanup_removes_all_resources
    transport = SmartMessage::Transport::NamedPipes.new(**@options)
    transport.configure

    # Create multiple pipes
    channels = %w[cleanup1 cleanup2 cleanup3]
    channels.each do |channel|
      transport.send(:create_subscriber_pipe, channel)
    end

    # Verify pipes exist
    channels.each do |channel|
      pipe_name = transport.send(:subscriber_pipe_name, channel)
      assert File.exist?(pipe_name)
    end

    # Cleanup
    transport.send(:cleanup_pipes)

    # Verify pipes are removed
    channels.each do |channel|
      pipe_name = transport.send(:subscriber_pipe_name, channel)
      refute File.exist?(pipe_name), "Pipe #{pipe_name} should be removed"
    end
  end

  def test_graceful_shutdown
    transport = SmartMessage::Transport::NamedPipes.new(**@options)
    transport.configure

    # Set shutdown flag
    transport.instance_variable_set(:@shutdown, true)

    # Connected should return false
    refute transport.connected?
  end

  def test_connect_and_disconnect
    transport = SmartMessage::Transport::NamedPipes.new(**@options)

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

  def test_channel_name_derivation_edge_cases
    transport = SmartMessage::Transport::NamedPipes.new(**@options)
    transport.configure

    # Test various class name formats
    test_cases = {
      "SimpleClass" => "simpleclass",
      "Namespace::ClassName" => "namespace_classname",
      "Deep::Nested::Class::Name" => "deep_nested_class_name",
      "ALLCAPS" => "allcaps",
      "Mixed_Case_123" => "mixed_case_123"
    }

    test_cases.each do |input, expected|
      result = transport.send(:derive_channel_name, input)
      assert_equal expected, result, "Failed for input: #{input}"
    end
  end

  def test_pipe_permissions
    transport = SmartMessage::Transport::NamedPipes.new(**@options)
    transport.configure

    channel_name = "permission_test"
    transport.send(:create_subscriber_pipe, channel_name)

    pipe_name = transport.send(:subscriber_pipe_name, channel_name)
    stat = File.stat(pipe_name)

    # Check that permissions are set correctly (0600)
    assert_equal 0600, stat.mode & 0777
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

    # Cleanup transport1 shouldn't affect transport2's ability to use pipes
    # (though it will remove the pipes - this tests the idempotency)
    transport1.disconnect
    transport2.disconnect
  end
end

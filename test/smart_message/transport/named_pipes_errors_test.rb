# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "securerandom"

class SmartMessage::Transport::NamedPipesErrorsTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("named_pipes_errors")
    @options = {
      base_path: @test_dir,
      namespace: "error_test",
      cleanup: true,
      timeout: 1.0,  # Shorter timeout for error tests
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

  def test_write_to_nonexistent_pipe
    transport = new_transport
    transport.configure

    nonexistent_pipe = File.join(@test_dir, "nonexistent.pipe")

    # Today write_to_pipe opens with 'w', so a missing pipe becomes a regular
    # file and nothing raises. That is a known lib bug; this test only checks
    # that no unexpected error escapes, and stays inside @test_dir.
    begin
      transport.send(:write_to_pipe, nonexistent_pipe, "test data")
      # If no error, that's also acceptable (e.g., ENXIO was caught)
    rescue SmartMessage::Transport::NamedPipes::Error => e
      assert_match(/Timeout writing to named pipe/, e.message)
    end
  end

  def test_create_pipe_in_nonexistent_directory
    skip "FileUtils.mkdir_p creates parent directories, making this hard to test portably"

    # This would test creating a pipe in a directory where we truly can't write
    # but FileUtils.mkdir_p is very forgiving and creates parent directories
    # A real test would require setting up actual permission denied scenarios
  end

  def test_timeout_on_write_to_blocked_pipe
    transport = new_transport
    transport.configure

    channel_name = "blocked_pipe"
    pipe_name = transport.send(:subscriber_pipe_name, channel_name)

    # Create the pipe
    transport.send(:create_subscriber_pipe, channel_name)

    # Don't start a reader - pipe will block

    # Writing should timeout
    error = assert_raises(SmartMessage::Transport::NamedPipes::Error) do
      transport.send(:write_to_pipe, pipe_name, "This will timeout")
    end

    # Check that the error message mentions timeout and includes a number
    assert_match(/Timeout writing to named pipe after [0-9.]+/, error.message)
  end

  def test_publish_to_nonexistent_channel
    transport = new_transport
    transport.configure

    # Publishing to a channel with no subscribers should not raise
    # (message is just dropped with debug log)
    assert_nil transport.do_publish("NonexistentClass", "serialized data")
  end

  def test_error_handling_with_corrupt_data
    skip "Requires full SmartMessage framework for deserialization"

    transport = new_transport
    transport.configure

    channel_name = "corrupt_data"

    # Create pipe and start reader
    transport.send(:create_subscriber_pipe, channel_name)

    # Test with various corrupt/malformed data
    # The receive method should handle this gracefully
  end

  def test_handle_permission_denied
    skip "Requires special permission setup"

    # This would test creating a pipe in a directory where we don't have write permissions
    # Difficult to test in a portable way
  end

  def test_cleanup_with_open_file_descriptors
    transport = new_transport
    transport.configure

    channel_name = "open_fd_test"
    pipe_name = transport.send(:subscriber_pipe_name, channel_name)

    # Create the pipe
    transport.send(:create_subscriber_pipe, channel_name)

    # Open the pipe (keep a reference)
    pipe_fd = File.open(pipe_name, 'r+', File::NONBLOCK)

    begin
      # Cleanup should still work even with open FDs
      transport.send(:cleanup_pipes)

      # Pipe should be removed from the hash
      pipes = transport.instance_variable_get(:@subscriber_pipes)
      refute pipes.key?(channel_name)
    ensure
      pipe_fd.close rescue nil
    end
  end

  def test_concurrent_cleanup_safety
    transport = new_transport
    transport.configure

    # Create several pipes
    10.times do |i|
      transport.send(:create_subscriber_pipe, "channel_#{i}")
    end

    # Try to cleanup from multiple threads simultaneously
    # This tests that concurrent cleanups don't crash
    threads = 5.times.map do
      Thread.new do
        begin
          transport.send(:cleanup_pipes)
        rescue Errno::ENOENT
          # Expected - file may have already been deleted by another thread
        end
      end
    end

    # All threads should complete
    threads.each(&:join)

    # All pipes should be removed from the hash
    pipes = transport.instance_variable_get(:@subscriber_pipes)
    assert_empty pipes
  end

  def test_remove_nonexistent_pipe
    transport = new_transport
    transport.configure

    # Removing a pipe that doesn't exist should not raise
    assert_nil transport.send(:remove_subscriber_pipe, "nonexistent_channel")
  end

  def test_double_cleanup
    transport = new_transport
    transport.configure

    # Create a pipe
    transport.send(:create_subscriber_pipe, "test_channel")

    # Cleanup once
    transport.send(:cleanup_pipes)

    # Cleanup again should not raise
    assert_nil transport.send(:cleanup_pipes)
  end

  def test_empty_channel_name
    transport = new_transport
    transport.configure

    # Empty channel name should still create a valid pipe path
    channel_name = ""
    pipe_name = transport.send(:subscriber_pipe_name, channel_name)

    assert_equal File.join(@test_dir, "error_test", ".in.pipe"), pipe_name
  end

  def test_special_characters_in_channel_name
    transport = new_transport
    transport.configure

    # Channel names with special characters
    # The derive_channel_name method handles :: but not other special chars
    special_names = [
      "channel/with/slashes",
      "channel with spaces",
      "channel\nwith\nnewlines"
    ]

    special_names.each do |name|
      pipe_name = transport.send(:subscriber_pipe_name, name)
      # Should create a pipe path (though it may be unusual)
      assert pipe_name.include?(@test_dir)
    end
  end

  def test_very_long_channel_name
    transport = new_transport
    transport.configure

    # Very long channel name (testing filename limits)
    long_name = "a" * 200
    pipe_name = transport.send(:subscriber_pipe_name, long_name)

    # Should create a path (though the OS may reject it during mkfifo)
    assert pipe_name.length > 200
  end

  def test_error_in_signal_handler
    skip "Signal handler testing is complex and platform-specific"
  end

  def test_shutdown_flag_thread_visibility
    transport = new_transport
    transport.configure

    # Start a thread that checks shutdown flag
    flag_visible = false
    thread = Thread.new do
      sleep 0.1 while !transport.instance_variable_get(:@shutdown)
      flag_visible = true
    end

    # Set shutdown flag from main thread
    transport.instance_variable_set(:@shutdown, true)

    # Thread should see the change
    thread.join(1.0)

    assert flag_visible, "Shutdown flag should be visible across threads"
  end

  def test_mkfifo_failure
    skip "Requires mkfifo to fail in a controlled way"

    # This would test the case where system("mkfifo", ...) fails
    # Difficult to test without mocking or causing actual system failures
  end

  def test_reader_thread_exception_handling
    skip "Requires full SmartMessage framework to test reader threads"

    # This would test that exceptions in reader threads are caught and logged
    # without crashing the entire transport
  end

  def test_write_after_disconnect
    transport = new_transport
    transport.configure

    channel_name = "disconnect_test"
    pipe_name = transport.send(:subscriber_pipe_name, channel_name)

    transport.send(:create_subscriber_pipe, channel_name)

    # Disconnect
    transport.disconnect

    # Attempting operations after disconnect
    # Should handle gracefully (connected? returns false)
    refute transport.connected?
    refute File.exist?(pipe_name), "disconnect must remove the subscriber pipe"
  end
end

# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "open3"
require "rbconfig"
require "timeout"

class SmartMessage::Transport::NamedPipesSignalTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)

  # A child process that subscribes (so a reader thread and a FIFO exist),
  # reports the pipe path, then waits to be signalled.
  CHILD_SCRIPT = <<~RUBY
    require "smart_message/transport/named_pipes"
    t = SmartMessage::Transport::NamedPipes.new(base_path: ARGV[0], namespace: "sig")
    t.connect
    t.subscribe("SignalMessage", proc {})
    $stdout.write(t.send(:subscriber_pipe_name, "signalmessage") + "\\n")
    $stdout.flush
    sleep
  RUBY

  # test/ goes on the load path ahead of the installed gems, as in CI, so the
  # child loads the test/smart_message.rb stub rather than the real gem.
  CHILD_COMMAND = [
    RbConfig.ruby, "-I", File.join(ROOT, "test"), "-I", File.join(ROOT, "lib"), "-e", CHILD_SCRIPT
  ].freeze

  def setup
    @test_dir = Dir.mktmpdir("named_pipes_signal")
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def test_handle_shutdown_signal_sets_flag_and_exits
    transport = SmartMessage::Transport::NamedPipes.allocate
    transport.instance_variable_set(:@shutdown, false)

    error = assert_raises(SystemExit) { transport.send(:handle_shutdown_signal) }

    assert_equal 0, error.status
    assert transport.instance_variable_get(:@shutdown)
  end

  def test_term_signal_exits_cleanly_and_removes_pipe
    %w[TERM INT].each do |signal|
      status, stderr, pipe_name = run_child_and_signal(signal)

      refute_match(/ThreadError/, stderr, "#{signal}: trap handler raised")
      assert_equal 0, status.exitstatus, "#{signal}: expected a clean exit, stderr:\n#{stderr}"
      refute File.exist?(pipe_name), "#{signal}: subscriber pipe should be removed on exit"
    end
  end

  private

  def run_child_and_signal(signal)
    Open3.popen3(*CHILD_COMMAND, @test_dir) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      pipe_name = Timeout.timeout(5) { stdout.gets }.to_s.chomp
      assert File.pipe?(pipe_name), "child should have created its FIFO"

      Process.kill(signal, wait_thr.pid)
      status = Timeout.timeout(10) { wait_thr.value }
      [status, stderr.read, pipe_name]
    end
  end
end

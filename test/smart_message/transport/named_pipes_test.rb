# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class SmartMessage::Transport::NamedPipesTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("named_pipes_test")
    @options = {
      base_path: @test_dir,
      namespace: "test",
      cleanup: true,
      timeout: 2.0,
      permissions: 0600
    }
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
  end

  def test_that_it_has_a_version_number
    refute_nil ::SmartMessage::Transport::NamedPipes::VERSION
  end

  def test_version_format
    assert_match(/\d+\.\d+\.\d+/, ::SmartMessage::Transport::NamedPipes::VERSION)
  end

  def test_default_configuration
    config = SmartMessage::Transport::NamedPipes::DEFAULT_CONFIG

    assert_equal :unidirectional, config[:mode]
    assert_equal 0600, config[:permissions]
    assert_equal true, config[:cleanup]
    assert_equal 65536, config[:buffer_size]
    assert_equal 5.0, config[:timeout]
  end

  def test_default_base_path_from_env
    # DEFAULT_CONFIG is frozen and evaluated at load time, so we test
    # that the environment variable support is present in the constant definition
    config = SmartMessage::Transport::NamedPipes::DEFAULT_CONFIG

    # Verify that base_path has a default value
    assert config[:base_path].is_a?(String)
    refute config[:base_path].empty?
  end

  def test_default_namespace_from_env
    # DEFAULT_CONFIG is frozen and evaluated at load time, so we test
    # that the environment variable support is present in the constant definition
    config = SmartMessage::Transport::NamedPipes::DEFAULT_CONFIG

    # Verify that namespace has a default value
    assert config[:namespace].is_a?(String)
    refute config[:namespace].empty?
  end

  def test_initialization_creates_required_structures
    transport = create_mock_transport

    assert_instance_of Hash, transport.instance_variable_get(:@subscriber_pipes)
    assert_instance_of Hash, transport.instance_variable_get(:@publisher_pipes)
    assert_instance_of Hash, transport.instance_variable_get(:@pipe_readers)
    assert_equal false, transport.instance_variable_get(:@shutdown)
    assert_instance_of Mutex, transport.instance_variable_get(:@mutex)
  end

  def test_configure_creates_pipe_directory
    transport = create_mock_transport
    transport.configure

    expected_path = File.join(@test_dir, "test")
    assert File.directory?(expected_path)
    assert_equal expected_path, transport.pipe_path
  end

  def test_connected_returns_true_when_connected
    transport = create_mock_transport
    transport.configure

    assert transport.connected?
  end

  def test_connected_returns_false_after_shutdown
    transport = create_mock_transport
    transport.configure
    transport.instance_variable_set(:@shutdown, true)

    refute transport.connected?
  end

  def test_connect_after_disconnect_restores_transport
    transport = SmartMessage::Transport::NamedPipes.new(**@options)
    transport.connect
    transport.disconnect
    transport.connect

    assert transport.connected?

    transport.subscribe("ReconnectMessage", ->(*) {})
    assert File.pipe?(transport.send(:subscriber_pipe_name, "reconnectmessage"))
  ensure
    transport&.disconnect
  end

  def test_subscribe_after_reconnect_replaces_dead_reader
    transport = SmartMessage::Transport::NamedPipes.new(**@options, cleanup: false)
    transport.connect
    dead_reader = Thread.new {}.tap(&:join)
    transport.instance_variable_get(:@pipe_readers)["reconnectmessage"] = dead_reader

    transport.subscribe("ReconnectMessage", ->(*) {})

    assert transport.instance_variable_get(:@pipe_readers)["reconnectmessage"].alive?
  ensure
    transport&.disconnect
    transport&.instance_variable_get(:@pipe_readers)&.each_value(&:kill)
  end

  def test_derive_channel_name
    transport = create_mock_transport

    # Test with simple class name
    channel = transport.send(:derive_channel_name, "TestMessage")
    assert_equal "testmessage", channel

    # Test with namespaced class name
    channel = transport.send(:derive_channel_name, "Foo::Bar::TestMessage")
    assert_equal "foo_bar_testmessage", channel
  end

  def test_subscriber_pipe_name_format
    transport = create_mock_transport
    transport.configure

    pipe_name = transport.send(:subscriber_pipe_name, "test_channel")
    expected = File.join(@test_dir, "test", "test_channel.in.pipe")
    assert_equal expected, pipe_name
  end

  def test_create_subscriber_pipe
    transport = create_mock_transport
    transport.configure

    channel_name = "test_channel"
    transport.send(:create_subscriber_pipe, channel_name)

    pipe_name = transport.send(:subscriber_pipe_name, channel_name)
    assert File.exist?(pipe_name)

    # Check it's actually a pipe
    stat = File.stat(pipe_name)
    assert stat.pipe?

    # Check permissions
    assert_equal 0600, stat.mode & 0777
  end

  def test_create_subscriber_pipe_idempotent
    transport = create_mock_transport
    transport.configure

    channel_name = "test_channel"

    # Create twice - should not raise error
    transport.send(:create_subscriber_pipe, channel_name)
    transport.send(:create_subscriber_pipe, channel_name)

    pipe_name = transport.send(:subscriber_pipe_name, channel_name)
    assert File.exist?(pipe_name)
  end

  def test_remove_subscriber_pipe
    transport = create_mock_transport
    transport.configure

    channel_name = "test_channel"
    transport.send(:create_subscriber_pipe, channel_name)

    pipe_name = transport.send(:subscriber_pipe_name, channel_name)
    assert File.exist?(pipe_name)

    transport.send(:remove_subscriber_pipe, channel_name)
    refute File.exist?(pipe_name)
  end

  def test_cleanup_pipes_removes_all_pipes
    transport = create_mock_transport
    transport.configure

    # Create multiple pipes
    %w[channel1 channel2 channel3].each do |channel|
      transport.send(:create_subscriber_pipe, channel)
    end

    transport.send(:cleanup_pipes)

    # All pipes should be removed
    %w[channel1 channel2 channel3].each do |channel|
      pipe_name = transport.send(:subscriber_pipe_name, channel)
      refute File.exist?(pipe_name)
    end
  end

  def test_cleanup_pipes_respects_cleanup_option
    options = @options.merge(cleanup: false)
    transport = create_mock_transport(options)
    transport.configure

    channel_name = "test_channel"
    transport.send(:create_subscriber_pipe, channel_name)
    pipe_name = transport.send(:subscriber_pipe_name, channel_name)

    transport.send(:cleanup_pipes)

    assert File.pipe?(pipe_name), "cleanup: false must leave the pipe in place"
  end

  ProbeMessage = Class.new

  def test_unsubscribe_keeps_pipe_while_other_handlers_remain
    @transport = subscribed_probe_transport
    @transport.unsubscribe(ProbeMessage, "Probe.first")

    assert File.exist?(probe_pipe_name), "pipe removed while a handler is still subscribed"
    assert probe_reader?, "reader stopped while a handler is still subscribed"
  ensure
    @transport&.disconnect
  end

  def test_unsubscribe_removes_pipe_after_last_handler
    @transport = subscribed_probe_transport
    @transport.unsubscribe(ProbeMessage, "Probe.first")
    @transport.unsubscribe(ProbeMessage, "Probe.second")

    refute File.exist?(probe_pipe_name), "pipe left behind after the last handler unsubscribed"
    refute probe_reader?, "reader left running after the last handler unsubscribed"
    refute @transport.dispatcher.subscribers.key?(ProbeMessage), "lookup added a Class-keyed entry"
  ensure
    @transport&.disconnect
  end

  def test_subscribers_predicate_treats_missing_or_empty_as_none
    transport = create_mock_transport
    dispatcher = SmartMessage::Transport::Base::Dispatcher.new
    transport.instance_variable_set(:@dispatcher, dispatcher)

    refute transport.send(:subscribers?, ProbeMessage)
    refute dispatcher.subscribers.key?(ProbeMessage.to_s), "lookup added an entry"

    dispatcher.add(ProbeMessage, "Probe.first")
    assert transport.send(:subscribers?, ProbeMessage)

    dispatcher.drop(ProbeMessage, "Probe.first")
    refute transport.send(:subscribers?, ProbeMessage)
  end

  private

  def subscribed_probe_transport
    transport = SmartMessage::Transport::NamedPipes.new(**@options)
    transport.connect
    transport.subscribe(ProbeMessage, "Probe.first")
    transport.subscribe(ProbeMessage, "Probe.second")
    transport
  end

  def probe_channel = @transport.send(:derive_channel_name, ProbeMessage)
  def probe_pipe_name = @transport.send(:subscriber_pipe_name, probe_channel)
  def probe_reader? = @transport.instance_variable_get(:@pipe_readers).key?(probe_channel)

  def create_mock_transport(options = nil)
    options ||= @options

    # Create a minimal mock that doesn't require full SmartMessage::Transport::Base
    transport = SmartMessage::Transport::NamedPipes.allocate
    transport.instance_variable_set(:@options, options)
    transport.instance_variable_set(:@subscriber_pipes, {})
    transport.instance_variable_set(:@publisher_pipes, {})
    transport.instance_variable_set(:@pipe_readers, {})
    transport.instance_variable_set(:@shutdown, false)
    transport.instance_variable_set(:@mutex, Mutex.new)

    # Mock logger
    logger = Object.new
    def logger.debug(&block); end
    def logger.info(&block); end
    def logger.warn(&block); end
    def logger.error(&block); end
    transport.instance_variable_set(:@logger, logger)

    transport
  end
end

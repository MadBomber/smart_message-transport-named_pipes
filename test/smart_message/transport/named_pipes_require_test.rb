# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class SmartMessage::Transport::NamedPipesRequireTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)

  # smart_message 0.1.0 loads through Zeitwerk: requiring only its
  # transport/base leaves SmartMessage::Dispatcher undefined, so the
  # transport must load the whole framework itself.
  def test_requiring_the_transport_loads_smart_message
    script = <<~RUBY
      require "smart_message/transport/named_pipes"
      exit($LOADED_FEATURES.any? { |f| f.end_with?("/smart_message.rb") })
    RUBY

    _out, err, status = Open3.capture3(
      RbConfig.ruby, "-I", File.join(ROOT, "test"), "-I", File.join(ROOT, "lib"), "-e", script
    )

    assert status.success?, "require \"smart_message\" was not loaded by the transport\n#{err}"
  end

  # The environment is read only by #default_options, so a variable that was
  # set at require time and later removed must not linger as a default.
  def test_env_vars_removed_after_require_fall_back_to_literal_defaults
    script = <<~RUBY
      require "smart_message/transport/named_pipes"
      ENV.delete("SMART_MESSAGE_PIPE_BASE")
      ENV.delete("SMART_MESSAGE_NAMESPACE")
      klass = SmartMessage::Transport::NamedPipes
      print [klass::DEFAULT_CONFIG.values_at(:base_path, :namespace),
             klass.allocate.default_options.values_at(:base_path, :namespace)].flatten.join(",")
    RUBY

    out, err, status = Open3.capture3(
      { "SMART_MESSAGE_PIPE_BASE" => "/early/base", "SMART_MESSAGE_NAMESPACE" => "early" },
      RbConfig.ruby, "-I", File.join(ROOT, "test"), "-I", File.join(ROOT, "lib"), "-e", script
    )

    assert status.success?, err
    assert_equal "/tmp/smart_message/pipes,default,/tmp/smart_message/pipes,default", out
  end
end

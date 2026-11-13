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
end

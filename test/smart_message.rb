# frozen_string_literal: true

# Test-only stand-in for the smart_message gem's entry point. The suite runs
# with -Itest, so `require "smart_message"` in the transport resolves here and
# loads the repo's stub Base instead of needing the real gem installed.
require "smart_message/transport/base"

## [Unreleased]

### Added
- GitHub Actions CI running the test suite directly on Ruby 3.2–3.4 and 4.0

### Removed
- Removed the unused private `publisher_pipe_name` helper (dead code)
- Removed two error tests that could never fail (#59)
- Removed integration and error tests that duplicated unit tests or could not fail; merged the channel-name edge cases into the unit test (#64)

### Changed
- Single-source the VERSION constant via version.rb
- Stop packaging the test-only transport/base.rb stub in the gem
- Un-skipped the multiple-messages integration test with a read-write reader (#46)
- Added tests for the publish timeout and system-error paths (#63)
- The test stub logger now evaluates log message blocks, so errors inside them fail the suite (#60)
- Replaced six skip-only error tests with real tests for pipe-creation failures (#45)
- Gemspec metadata: add bug tracker, documentation and MFA-required URIs; drop duplicate homepage_uri

### Fixed
- `unsubscribe` and `disconnect` stop idle reader threads promptly instead of waiting ~2s per channel and killing them (#14)
- Messages are no longer lost under bursty publishing: the reader keeps its FIFO open between writers (#18)
- A message whose `receive` raises no longer drops the other messages read with it or stalls the channel (#23)
- `disconnect` with `cleanup: false` now stops reader threads; the option only controls pipe removal (#24)
- `SMART_MESSAGE_PIPE_BASE` and `SMART_MESSAGE_NAMESPACE` are honoured when set after the gem is required (#28)
- `subscribe` after `disconnect` raises a clear error instead of returning a subscription whose reader has already exited (#65)
- One transport's `disconnect` (or exit) no longer deletes the namespace directory other transports share; `subscribe` recreates the directory if it is missing (#62)
- `subscribe` raises when a class's channel is already bound to a different class (e.g. `Billing::Event` and `Billing_Event`) instead of silently delivering its messages as the first class (#61)
- `connect` after `disconnect` restores the transport instead of leaving it shut down (#17)
- Corrected README channel-derivation example and stale `Running Tests` file paths
- README timeout docs name the error class each publish path raises and note framework failures are dead-lettered (#67)
- README Thread Model no longer claims non-blocking I/O; it describes the polling reader and the timeout-bounded blocking write (#66)
- `unsubscribe` no longer removes the pipe and reader while other handlers for the class remain subscribed (#13)
- `unsubscribe!` now removes the subscriber pipe and stops its reader thread (#15)
- Requiring the transport now loads `smart_message` itself, so it works without a prior `require "smart_message"` (#41)
- Publishing to a removed pipe no longer leaves a regular file that blocks re-subscribing; a non-FIFO at the pipe path is refused (#40)
- INT/TERM no longer crash with `ThreadError` in the trap handler; cleanup runs from `at_exit` instead (#12)

## [0.0.1] - 2025-11-13

### Added
- Initial implementation of NamedPipes transport for SmartMessage
- Unix named pipes (FIFO) based inter-process communication
- Thread-safe operations with Mutex protection
- Configurable options for paths, permissions, timeouts, and namespaces
- Environment variable support (SMART_MESSAGE_PIPE_BASE, SMART_MESSAGE_NAMESPACE)
- Graceful shutdown with proper resource cleanup
- Signal handlers for INT and TERM signals
- Non-blocking I/O to prevent deadlocks
- Timeout protection on write operations
- Comprehensive error handling and logging
- Automatic pipe cleanup on disconnect
- Channel name derivation from message class names

### Documentation
- Comprehensive README with usage examples
- Configuration options documentation
- Architecture and performance documentation
- Troubleshooting guide
- Complete test suite with unit, integration, and error scenario tests

### Requirements
- Ruby >= 3.2.0
- Unix-like operating system (Linux, macOS, BSD)
- smart_message gem

## [Unreleased]

### Added
- GitHub Actions CI running the test suite directly on Ruby 3.2–3.4

### Removed
- Removed the unused private `publisher_pipe_name` helper (dead code)

### Changed
- Single-source the VERSION constant via version.rb
- Stop packaging the test-only transport/base.rb stub in the gem

### Fixed
- `disconnect` with `cleanup: false` now stops reader threads; the option only controls pipe removal (#24)
- `SMART_MESSAGE_PIPE_BASE` and `SMART_MESSAGE_NAMESPACE` are honoured when set after the gem is required (#28)
- `connect` after `disconnect` restores the transport instead of leaving it shut down (#17)
- Corrected README channel-derivation example and stale `Running Tests` file paths
- `unsubscribe` no longer removes the pipe and reader while other handlers for the class remain subscribed (#13)
- `unsubscribe!` now removes the subscriber pipe and stops its reader thread (#15)

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

## [Unreleased]

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

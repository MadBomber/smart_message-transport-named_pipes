# SmartMessage::Transport::NamedPipes

A Unix named pipes (FIFO) transport layer for the SmartMessage messaging system. This transport enables fast, efficient inter-process communication (IPC) between processes running on the same machine using named pipes.

## Features

- **Fast IPC Communication**: Direct kernel-level pipe communication with minimal overhead
- **Thread-Safe**: All operations are protected with mutexes for concurrent access
- **Graceful Shutdown**: Proper cleanup of resources and threads on disconnect
- **Configurable**: Flexible configuration options for permissions, timeouts, and paths
- **Namespace Support**: Isolate different applications using namespace configuration
- **Comprehensive Error Handling**: Detailed logging and error reporting
- **Zero External Dependencies**: Uses only Ruby standard library

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'smart_message-transport-named_pipes'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install smart_message-transport-named_pipes
```

## Requirements

- Ruby >= 3.2.0
- Unix-like operating system (Linux, macOS, BSD)
- `mkfifo` command available (standard on all Unix systems)
- `smart_message` gem

**Note**: Named pipes (FIFOs) are a Unix-specific feature. This transport will not work on Windows.

## Usage

### Basic Setup

```ruby
require 'smart_message'
require 'smart_message/transport/named_pipes'

# Create transport instance
transport = SmartMessage::Transport::NamedPipes.new(
  base_path: '/tmp/my_app/pipes',
  namespace: 'production',
  timeout: 5.0
)

# Connect the transport
transport.connect

# Subscribe to messages
transport.subscribe(MyMessage, method(:handle_message))

# Publish messages
transport.publish(MyMessage, my_message_instance)

# Disconnect when done
transport.disconnect
```

### Configuration Options

The transport accepts the following configuration options:

| Option | Default | Description |
|--------|---------|-------------|
| `base_path` | `/tmp/smart_message/pipes` or `ENV['SMART_MESSAGE_PIPE_BASE']` | Root directory for named pipes |
| `namespace` | `'default'` or `ENV['SMART_MESSAGE_NAMESPACE']` | Namespace for isolating applications |
| `mode` | `:unidirectional` | Pipe mode (`:unidirectional` recommended) |
| `permissions` | `0600` | Unix file permissions for pipes (owner read/write only) |
| `cleanup` | `true` | Automatically remove pipes on shutdown |
| `buffer_size` | `65536` | Buffer size in bytes (64KB) |
| `timeout` | `5.0` | Timeout in seconds for write operations |

### Environment Variables

You can configure defaults using environment variables:

```bash
export SMART_MESSAGE_PIPE_BASE=/var/run/my_app/pipes
export SMART_MESSAGE_NAMESPACE=production
```

### Complete Example

```ruby
require 'smart_message'
require 'smart_message/transport/named_pipes'

# Define your message class
class OrderCreated < SmartMessage::Base
  attribute :order_id, :string
  attribute :customer_name, :string
  attribute :total, :decimal
end

# Create and configure transport
transport = SmartMessage::Transport::NamedPipes.new(
  base_path: '/tmp/order_system/pipes',
  namespace: 'production',
  permissions: 0600,
  timeout: 3.0
)

transport.connect

# Subscribe to messages
def handle_order_created(message)
  puts "Order #{message.order_id} created for #{message.customer_name}"
  puts "Total: $#{message.total}"
end

transport.subscribe(OrderCreated, method(:handle_order_created))

# In another process or thread, publish messages
order = OrderCreated.new(
  order_id: 'ORD-12345',
  customer_name: 'John Doe',
  total: BigDecimal('99.99')
)

transport.publish(OrderCreated, order)

# Keep the subscriber running
sleep

# Cleanup on exit
transport.disconnect
```

## Architecture

### How It Works

1. **Named Pipes (FIFOs)**: Creates Unix named pipes in the filesystem at `{base_path}/{namespace}/{channel}.in.pipe`

2. **Channel Derivation**: Message class names are converted to channel names:
   - `OrderCreated` → `ordercreated`
   - `MyApp::Events::UserSignedUp` → `myapp_events_signedup`

3. **Publishing**: Opens the named pipe for writing and sends serialized message data

4. **Subscribing**: Creates a background thread that continuously reads from the named pipe

5. **Thread Safety**: All shared data structures are protected with mutex locks

### Thread Model

- One reader thread per subscribed channel
- Non-blocking I/O with timeouts to prevent hangs
- Graceful shutdown with thread join and cleanup

### Named Pipe Layout

```
{base_path}/
  {namespace}/
    channel1.in.pipe
    channel2.in.pipe
    ...
```

Example:
```
/tmp/smart_message/pipes/
  production/
    ordercreated.in.pipe
    usersignedup.in.pipe
    paymentprocessed.in.pipe
```

## Security Considerations

### File Permissions

By default, pipes are created with `0600` permissions (owner read/write only), ensuring that only the creating user can access them. Adjust this with the `permissions` option:

```ruby
# More permissive (same group can access)
transport = SmartMessage::Transport::NamedPipes.new(
  permissions: 0660  # Owner and group read/write
)
```

### Namespace Isolation

Use namespaces to isolate different environments or applications:

```ruby
# Development
dev_transport = SmartMessage::Transport::NamedPipes.new(namespace: 'development')

# Production
prod_transport = SmartMessage::Transport::NamedPipes.new(namespace: 'production')
```

### Cleanup

Set `cleanup: false` if you want pipes to persist after process exit (useful for debugging):

```ruby
transport = SmartMessage::Transport::NamedPipes.new(cleanup: false)
```

## Performance

### Benchmarks

Named pipes are extremely fast for IPC on the same machine:

- **Latency**: Sub-millisecond message delivery
- **Throughput**: Hundreds of thousands of messages per second
- **Memory**: Minimal overhead, kernel-buffered

### Tuning Tips

1. **Adjust buffer_size**: Increase for larger messages
   ```ruby
   transport = SmartMessage::Transport::NamedPipes.new(buffer_size: 131072)  # 128KB
   ```

2. **Reduce timeout**: For faster failure detection
   ```ruby
   transport = SmartMessage::Transport::NamedPipes.new(timeout: 1.0)  # 1 second
   ```

3. **Use multiple pipes**: Subscribe different message types in different processes for parallelism

4. **Monitor pipe directory**: Ensure `/tmp` or custom `base_path` has sufficient space and inodes

## Troubleshooting

### Pipe Timeout Errors

**Error**: `Timeout writing to named pipe after N seconds`

**Cause**: No subscriber is reading from the pipe

**Solution**:
- Ensure subscriber process is running
- Check that subscriber has subscribed to the correct message class
- Verify namespace matches between publisher and subscriber

### Permission Denied

**Error**: `Errno::EACCES` when creating pipes

**Cause**: Insufficient permissions to create files in `base_path`

**Solution**:
- Choose a directory where the process has write permissions
- Use `/tmp` or user's home directory
- Run with appropriate user permissions

### Pipes Not Cleaned Up

**Issue**: Old pipe files remain after process exit

**Cause**: Process was killed forcefully (SIGKILL) or `cleanup: false`

**Solution**:
- Use `SIGTERM` or `SIGINT` for graceful shutdown
- Set `cleanup: true` (default)
- Manually clean up: `rm -rf {base_path}/{namespace}/*.pipe`

### Reader Thread Not Starting

**Issue**: Messages published but not received

**Cause**: Subscriber not properly initialized

**Solution**:
```ruby
# Ensure you call subscribe AFTER connect
transport.connect
transport.subscribe(MyMessage, method(:handler))
```

## Comparison with Other Transports

| Feature | NamedPipes | TCP/IP | Redis | RabbitMQ |
|---------|------------|--------|-------|----------|
| Latency | Very Low | Low | Medium | Medium |
| Throughput | Very High | High | High | Medium |
| Network | No | Yes | Yes | Yes |
| Persistence | No | No | Optional | Yes |
| Setup Complexity | Minimal | Low | Medium | High |
| External Dependencies | None | None | Redis | RabbitMQ |

**Use Named Pipes when**:
- All processes run on the same machine
- You need the lowest latency possible
- You want minimal dependencies
- You don't need message persistence

**Use other transports when**:
- Processes run on different machines
- You need message persistence
- You need advanced routing features
- You need message durability guarantees

## Development

After checking out the repo, run `bundle install` to install dependencies.

### Running Tests

```bash
# Run all tests
ruby -Ilib:test test/smart_message/transport/test_named_pipes.rb
ruby -Ilib:test test/smart_message/transport/test_named_pipes_integration.rb
ruby -Ilib:test test/smart_message/transport/test_named_pipes_errors.rb

# Or using rake (if available)
rake test
```

### Code Style

```bash
rubocop
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MadBomber/smart_message-transport-named_pipes.

### Development Guidelines

1. Write tests for new features
2. Follow existing code style
3. Update documentation
4. Add entries to CHANGELOG.md

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Related Projects

- [smart_message](https://github.com/MadBomber/smart_message) - Core messaging framework
- Other SmartMessage transports:
  - `smart_message-transport-tcp` - TCP/IP transport
  - `smart_message-transport-redis` - Redis pub/sub transport
  - `smart_message-transport-http` - HTTP/webhook transport

## Support

For issues, questions, or contributions, please visit:
- GitHub Issues: https://github.com/MadBomber/smart_message-transport-named_pipes/issues
- Documentation: https://github.com/MadBomber/smart_message-transport-named_pipes

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.

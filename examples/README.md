# SmartMessage::Transport::NamedPipes Examples

This directory contains example code demonstrating how to use the NamedPipes transport.

## Examples

### 1. basic_pubsub.rb

Demonstrates basic publish/subscribe functionality.

**To run:**

Terminal 1 (Subscriber):
```bash
ruby examples/basic_pubsub.rb subscribe
```

Terminal 2 (Publisher):
```bash
ruby examples/basic_pubsub.rb publish
```

**What it does:**
- Sets up a named pipes transport
- Subscriber waits for greeting messages
- Publisher sends 5 greeting messages
- Shows basic message flow

### 2. multiple_processes.rb

Demonstrates multiple processes handling different message types.

**To run:**
```bash
ruby examples/multiple_processes.rb
```

**What it does:**
- Forks 3 worker processes for different message types
- Each worker subscribes to one message type
- Main process publishes order lifecycle events
- Shows parallel message processing

## Prerequisites

Before running examples, ensure you have:

1. Installed the gem and dependencies:
   ```bash
   bundle install
   ```

2. Required permissions to create pipes in `/tmp/smart_message_examples/pipes`

## Notes

- Examples use `/tmp/smart_message_examples/pipes` as the base path
- Each example uses a different namespace to avoid conflicts
- Press Ctrl+C to exit subscriber processes
- Pipes are automatically cleaned up on exit

## Troubleshooting

**Issue**: "No subscriber pipe found" message

**Solution**: Make sure the subscriber is started before the publisher

**Issue**: Permission denied errors

**Solution**: Check that you have write permissions to `/tmp`

**Issue**: Timeout errors

**Solution**: Increase the timeout in transport configuration:
```ruby
SmartMessage::Transport::NamedPipes.new(timeout: 10.0)
```

## Customization

You can modify the examples to experiment with:

- Different message structures
- Multiple subscribers per message type
- Custom namespaces and paths
- Different timeout values
- Permission settings

## More Information

See the main [README.md](../README.md) for complete documentation.

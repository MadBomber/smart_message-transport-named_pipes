#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic pub/sub example for SmartMessage::Transport::NamedPipes
#
# This example demonstrates basic publish/subscribe functionality using named pipes.
#
# Usage:
#   1. Start the subscriber in one terminal: ruby examples/basic_pubsub.rb subscribe
#   2. Start the publisher in another terminal: ruby examples/basic_pubsub.rb publish

require 'bundler/setup'
require 'smart_message'
require 'smart_message/transport/named_pipes'

# Define a simple message class
class GreetingMessage < SmartMessage::Base
  attribute :name, :string
  attribute :greeting, :string
  attribute :timestamp, :time
end

# Configure the transport
def create_transport
  SmartMessage::Transport::NamedPipes.new(
    base_path: '/tmp/smart_message_examples/pipes',
    namespace: 'basic_example',
    cleanup: true,
    timeout: 3.0
  )
end

# Subscriber process
def run_subscriber
  puts "Starting subscriber..."

  transport = create_transport
  transport.connect

  # Define message handler
  def handle_greeting(message)
    puts "\n📨 Received greeting:"
    puts "  From: #{message.name}"
    puts "  Message: #{message.greeting}"
    puts "  Time: #{message.timestamp}"
  end

  # Subscribe to GreetingMessage
  transport.subscribe(GreetingMessage, method(:handle_greeting))

  puts "Subscriber ready! Waiting for messages..."
  puts "Press Ctrl+C to exit"

  # Keep running
  begin
    sleep
  rescue Interrupt
    puts "\nShutting down subscriber..."
    transport.disconnect
  end
end

# Publisher process
def run_publisher
  puts "Starting publisher..."

  transport = create_transport
  transport.connect

  puts "Publishing 5 greeting messages..."

  greetings = [
    { name: "Alice", greeting: "Hello, World!" },
    { name: "Bob", greeting: "Good morning!" },
    { name: "Charlie", greeting: "How are you?" },
    { name: "Diana", greeting: "Nice to meet you!" },
    { name: "Eve", greeting: "Have a great day!" }
  ]

  greetings.each_with_index do |data, index|
    message = GreetingMessage.new(
      name: data[:name],
      greeting: data[:greeting],
      timestamp: Time.now
    )

    puts "#{index + 1}. Publishing: #{data[:name]} - #{data[:greeting]}"
    transport.publish(GreetingMessage, message)

    sleep 1 # Pause between messages
  end

  puts "\nAll messages published!"
  transport.disconnect
end

# Main entry point
if ARGV[0] == 'subscribe'
  run_subscriber
elsif ARGV[0] == 'publish'
  run_publisher
else
  puts "Usage:"
  puts "  ruby #{__FILE__} subscribe  # Start subscriber"
  puts "  ruby #{__FILE__} publish    # Start publisher"
  exit 1
end

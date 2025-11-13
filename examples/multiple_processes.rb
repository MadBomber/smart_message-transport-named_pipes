#!/usr/bin/env ruby
# frozen_string_literal: true

# Multiple process example for SmartMessage::Transport::NamedPipes
#
# This example demonstrates multiple processes subscribing to different message types.
#
# Usage:
#   ruby examples/multiple_processes.rb

require 'bundler/setup'
require 'smart_message'
require 'smart_message/transport/named_pipes'

# Define different message types
class OrderCreated < SmartMessage::Base
  attribute :order_id, :string
  attribute :customer_name, :string
  attribute :total, :decimal
end

class PaymentProcessed < SmartMessage::Base
  attribute :payment_id, :string
  attribute :order_id, :string
  attribute :amount, :decimal
  attribute :status, :string
end

class ShipmentDispatched < SmartMessage::Base
  attribute :shipment_id, :string
  attribute :order_id, :string
  attribute :carrier, :string
  attribute :tracking_number, :string
end

def create_transport
  SmartMessage::Transport::NamedPipes.new(
    base_path: '/tmp/smart_message_examples/pipes',
    namespace: 'multi_process',
    cleanup: true,
    timeout: 3.0
  )
end

# Fork worker processes for each message type
def start_order_processor
  fork do
    Process.setproctitle("order_processor")

    transport = create_transport
    transport.connect

    def handle_order(message)
      puts "[ORDER] 📦 New order received:"
      puts "        ID: #{message.order_id}"
      puts "        Customer: #{message.customer_name}"
      puts "        Total: $#{message.total}"
    end

    transport.subscribe(OrderCreated, method(:handle_order))

    puts "[ORDER] Processor ready..."
    sleep
  end
end

def start_payment_processor
  fork do
    Process.setproctitle("payment_processor")

    transport = create_transport
    transport.connect

    def handle_payment(message)
      puts "[PAYMENT] 💳 Payment processed:"
      puts "          Payment ID: #{message.payment_id}"
      puts "          Order ID: #{message.order_id}"
      puts "          Amount: $#{message.amount}"
      puts "          Status: #{message.status}"
    end

    transport.subscribe(PaymentProcessed, method(:handle_payment))

    puts "[PAYMENT] Processor ready..."
    sleep
  end
end

def start_shipment_processor
  fork do
    Process.setproctitle("shipment_processor")

    transport = create_transport
    transport.connect

    def handle_shipment(message)
      puts "[SHIPMENT] 🚚 Shipment dispatched:"
      puts "           Shipment ID: #{message.shipment_id}"
      puts "           Order ID: #{message.order_id}"
      puts "           Carrier: #{message.carrier}"
      puts "           Tracking: #{message.tracking_number}"
    end

    transport.subscribe(ShipmentDispatched, method(:handle_shipment))

    puts "[SHIPMENT] Processor ready..."
    sleep
  end
end

def start_publisher
  sleep 2 # Wait for subscribers to be ready

  puts "\n[PUBLISHER] Starting to publish events...\n\n"

  transport = create_transport
  transport.connect

  # Simulate order lifecycle
  order_id = "ORD-#{rand(10000..99999)}"

  # 1. Order created
  order = OrderCreated.new(
    order_id: order_id,
    customer_name: "John Doe",
    total: BigDecimal("149.99")
  )
  puts "[PUBLISHER] Publishing OrderCreated..."
  transport.publish(OrderCreated, order)
  sleep 1

  # 2. Payment processed
  payment = PaymentProcessed.new(
    payment_id: "PAY-#{rand(10000..99999)}",
    order_id: order_id,
    amount: BigDecimal("149.99"),
    status: "completed"
  )
  puts "[PUBLISHER] Publishing PaymentProcessed..."
  transport.publish(PaymentProcessed, payment)
  sleep 1

  # 3. Shipment dispatched
  shipment = ShipmentDispatched.new(
    shipment_id: "SHIP-#{rand(10000..99999)}",
    order_id: order_id,
    carrier: "FedEx",
    tracking_number: "1Z#{rand(100000000000000..999999999999999)}"
  )
  puts "[PUBLISHER] Publishing ShipmentDispatched..."
  transport.publish(ShipmentDispatched, shipment)

  puts "\n[PUBLISHER] All events published!"
  transport.disconnect

  sleep 2 # Give time for messages to be processed
end

# Main process
puts "Starting multiple process example..."
puts "This will start 3 worker processes + 1 publisher"
puts

# Start worker processes
order_pid = start_order_processor
payment_pid = start_payment_processor
shipment_pid = start_shipment_processor

# Publish events
start_publisher

# Cleanup
puts "\nCleaning up processes..."
Process.kill("TERM", order_pid)
Process.kill("TERM", payment_pid)
Process.kill("TERM", shipment_pid)

Process.waitall

puts "Done!"

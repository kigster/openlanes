# frozen_string_literal: true

require "redis-client"

module OpenLanes
  module Live
    # One Redis pub/sub connection, subscribed once to the channels and
    # patterns it was made with (plan 006's chat). A subscribed connection
    # can do nothing else, so it is its own connection, never the {Store}'s.
    #
    # Made by {Store#subscriber}; {MemorySubscriber} is the suite's.
    class Subscriber
      # Seconds the shortest wait lasts. redis-client reads a timeout of 0 as
      # "wait for ever", which is the one thing a polling loop must not do.
      SHORTEST = 0.01

      # @param url [String]
      # @param channels [Array<String>]
      # @param patterns [Array<String>]
      # @param timeout [Float] seconds to connect and to wait for each confirmation
      # @raise [OpenLanes::Live::Unavailable]
      def initialize(url:, channels: [], patterns: [], timeout: Store::TIMEOUT)
        @url = url
        guarded do
          @pubsub = RedisClient.config(url:, timeout:).new_client.pubsub
          @pubsub.call("SUBSCRIBE", *channels) unless channels.empty?
          @pubsub.call("PSUBSCRIBE", *patterns) unless patterns.empty?
          confirm(channels.size + patterns.size, timeout)
        end
      end

      # The next message, waiting up to +timeout+ seconds for one.
      #
      # @param timeout [Float]
      # @return [Array(String, String), nil] its channel and its payload
      # @raise [OpenLanes::Live::Unavailable]
      def next_message(timeout)
        loop do
          event = guarded { @pubsub.next_event([timeout, SHORTEST].max) } or return nil
          case event.first
          when "message" then return [event[1], event[2]]
          when "pmessage" then return [event[2], event[3]]
          end
        end
      end

      # @return [void]
      def close = @pubsub&.close

      private

      # Waits until Redis has confirmed every subscription, so a message
      # published the moment this returns is one this connection receives.
      #
      # @return [void]
      def confirm(expected, timeout)
        confirmed = 0
        while confirmed < expected
          event = @pubsub.next_event(timeout) or raise Unavailable, "Redis at #{Live.mask(@url)} did not confirm a subscription"
          confirmed += 1 if %w[subscribe psubscribe].include?(event.first)
        end
      end

      # @return [Object] the block's value
      # @raise [OpenLanes::Live::Unavailable]
      def guarded
        yield
      rescue RedisClient::Error => e
        raise Unavailable, "Redis at #{Live.mask(@url)} is unavailable: #{e.message.sub(/\s*\(redis:.*\)\z/, "")}"
      end
    end
  end
end

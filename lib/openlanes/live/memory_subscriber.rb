# frozen_string_literal: true

module OpenLanes
  module Live
    # {Subscriber}'s methods over {MemoryStore#publish}: a queue in this
    # process, matched by exact channel or by Redis-style glob.
    class MemorySubscriber
      # @param store [OpenLanes::Live::MemoryStore]
      # @param channels [Array<String>]
      # @param patterns [Array<String>]
      def initialize(store:, channels: [], patterns: [])
        @store = store
        @channels = channels
        @patterns = patterns
        @queue = Thread::Queue.new
      end

      # @param channel [String]
      # @return [Integer] how many of its subscriptions match, as Redis counts receivers
      def matches(channel)
        @channels.count(channel) + @patterns.count { File.fnmatch?(it, channel) }
      end

      # @param channel [String]
      # @param message [String]
      # @return [void]
      def deliver(channel, message) = matches(channel).times { @queue << [channel, message] }

      # @param timeout [Float]
      # @return [Array(String, String), nil]
      def next_message(timeout) = @queue.pop(timeout: [timeout, 0].max)

      # @return [void]
      def close
        @store.unsubscribe(self)
        @queue.close
      end
    end
  end
end

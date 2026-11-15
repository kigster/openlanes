# frozen_string_literal: true

require "json"

module OpenLanes
  module Slack
    # What the Slack worker learned, on its way to the store.
    #
    # The store's connection is not safe to share between threads, so the
    # worker never touches it. It queues what it wants written ({#save},
    # {#forget}, {#answer}) and the engine's loop writes it at the top of a
    # tick ({#drain}).
    class Outbox
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      def initialize(store:, keys:)
        @store = store
        @keys = keys
        @queue = Thread::Queue.new
        @pending = []
      end

      # The worker's side: remember where a poll is and how it stands.
      #
      # @param key [String] {Poll#key}
      # @param record [Hash]
      # @return [void]
      def save(key, record) = @queue << [:save, key, JSON.generate(record)]

      # The worker's side: a poll that is over.
      #
      # @param key [String]
      # @return [void]
      def forget(key) = @queue << [:forget, key]

      # The worker's side: what a person answered.
      #
      # @param command [Hash] an `answer` command, as {Live::Command} reads one
      # @return [void]
      def answer(command) = @queue << [:answer, command]

      # The loop's side: write everything queued. With Redis away, what is
      # left waits for it and is written in the same order.
      #
      # @return [void]
      def drain
        @pending << @queue.pop until @queue.empty?
        until @pending.empty?
          apply(@pending.first)
          @pending.shift
        end
      rescue Live::Unavailable
        nil
      end

      # The loop's side: the polls an earlier engine left open. Without
      # them an engine restarted with a question open would post it a
      # second time.
      #
      # @return [Hash{String => Hash}] records by {Poll#key}
      def records
        @store.hgetall(@keys.slack).transform_values { JSON.parse(it) }
      rescue Live::Unavailable, JSON::ParserError => e
        UI.log("slack: open polls not read back (#{e.message}); a question may be posted twice", level: :warn)
        {}
      end

      private

      # @param event [Array] what the worker queued
      # @return [void]
      def apply(event)
        kind, key, value = event
        case kind
        when :save then @store.hset(@keys.slack, key, value)
        when :forget then @store.hdel(@keys.slack, key)
        when :answer then Live.enqueue(store: @store, keys: @keys, input: key)
        end
      rescue Live::Command::Invalid => e
        UI.log("slack: answer not queued: #{e.message}", level: :warn)
      end
    end
  end
end

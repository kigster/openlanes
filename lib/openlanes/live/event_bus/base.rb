# frozen_string_literal: true

module OpenLanes
  module Live
    module EventBus
      # What every bus answers, delegated to the store behind it.
      class Base
        # @return [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
        attr_reader :store

        # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
        def initialize(store)
          @store = store
          freeze
        end

        # @param channel [String]
        # @param payload [String]
        # @return [Integer] how many subscriptions received it
        def publish(channel, payload) = store.publish(channel, payload)

        # A subscription of its own; the caller closes it.
        #
        # @param channels [Array<String>]
        # @param patterns [Array<String>]
        # @return [#next_message, #close]
        def subscribe(channels: [], patterns: []) = store.subscriber(channels:, patterns:)

        # A durable append, in stream order.
        #
        # @param stream [String]
        # @param fields [Hash]
        # @param maxlen [Integer, nil] approximate trim
        # @return [String] the entry id
        def append(stream, fields, maxlen: nil) = store.xadd(stream, fields, maxlen:)

        # The appends and writes the block makes, applied atomically.
        #
        # @yieldparam tx [OpenLanes::Live::EventBus::Transaction]
        # @return [void]
        def transaction
          store.multi { |raw| yield Transaction.new(raw) }
        end

        # The database pub/sub channel names carry (see {Keys#news}).
        #
        # @return [Integer]
        def db = store.db
      end
    end
  end
end

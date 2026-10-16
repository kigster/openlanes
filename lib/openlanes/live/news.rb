# frozen_string_literal: true

require "json"

module OpenLanes
  module Live
    # The nudge that tells every open page's event stream to look again
    # ({Keys#news}). It carries no data: whoever wrote something the page
    # shows writes it first, then publishes `{"kind": ...}`, and the stream
    # re-reads Redis as it always has. The data stays in its keys and
    # streams, so a nudge lost to a dropped connection costs latency, never
    # correctness, and the stream's cursors work exactly as before.
    #
    # Who publishes, and why each one does:
    #
    # - `board`: {Publisher}, on the Dispatcher's tick, only when the
    #   snapshot changed apart from its clock, so an idle engine is quiet.
    # - `reply`: {Commands}, on the Dispatcher's tick, for each reply.
    # - `copilot`: {Copilot}, in the API server, for each turn written.
    # - `app`: {Apps::Runner}, when a process changes state or the app stops.
    #   Its once-a-second heartbeat does not: nothing on the page moves.
    # - `chat`: {Chat}, after a step handed a page something to show.
    #   Its events live in this process, not in Redis, so the nudge is the
    #   only way a stream blocked on Redis can hear of them.
    # - `stop`: {Web::Server#stop}, so open streams end now rather than at
    #   their next ping.
    #
    # The `--demo` engine publishes `board` and `reply` the way the real one does.
    module News
      # Every kind a nudge may name. The stream does not branch on them; they
      # are there for whoever watches the channel with `redis-cli SUBSCRIBE`.
      KINDS = %w[board reply copilot app chat stop].freeze

      module_function

      # Nudge every stream following +keys+' project on +store+'s database.
      # Best effort: the write it announces is already in Redis, and a
      # stream that misses the nudge still finds it at its next ping.
      #
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @param kind [String] one of {KINDS}
      # @return [Integer] how many subscriptions heard it, 0 when Redis did not answer
      def publish(store:, keys:, kind:)
        store.publish(keys.news(db: store.db), JSON.generate(kind:))
      rescue Unavailable
        0
      end

      # A subscription of its own to the nudges, for one event stream. The
      # caller closes it: each is a Redis connection.
      #
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @return [OpenLanes::Live::Subscriber, OpenLanes::Live::MemorySubscriber]
      # @raise [OpenLanes::Live::Unavailable]
      def subscribe(store:, keys:) = store.subscriber(channels: [keys.news(db: store.db)])
    end
  end
end

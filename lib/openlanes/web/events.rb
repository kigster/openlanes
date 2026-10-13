# frozen_string_literal: true

require "json"

module OpenLanes
  module Web
    # One page's event stream (contract.md, `GET /api/events`): a `board`
    # event whenever any node's snapshot `seq` changes, a `reply` event for
    # each reply the engine writes, and a `: ping` comment so proxies and the
    # browser keep the connection open.
    #
    # Polled rather than blocked on: a blocking read would hold the thread's
    # connection for the length of the wait, and the board has to be looked
    # at every tick anyway.
    #
    # A reply carries its stream id as the event's `id:`, so a browser that
    # reconnects sends `Last-Event-ID` and gets what it missed. The stream
    # opens with a `cursor` event carrying the id it starts from, so a
    # browser that drops before the first reply still has one to send;
    # without it, replies written during that gap were skipped.
    class Events
      # @param context [OpenLanes::Web::Context]
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param last_id [String, nil] the `Last-Event-ID` the browser sent
      # @param clock [Proc] seconds, monotonic
      # @param sleeper [Proc] waits the given seconds between ticks
      def initialize(context:, store:, last_id: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
        sleeper: ->(seconds) { sleep seconds })
        @context = context
        @store = store
        @keys = context.keys
        @last_id = last_id.to_s.match?(/\A\d+-\d+\z/) ? last_id : nil
        @clock = clock
        @sleeper = sleeper
      end

      # Write events to +out+ until the browser leaves, the server stops, or
      # the context's lifetime runs out.
      #
      # @param out [#<<, #closed?]
      # @return [void]
      def run(out)
        started = @clock.call
        pinged = started
        cursor = @last_id || newest_reply
        out << self.class.frame("cursor", { id: cursor }, id: cursor)
        seqs = nil
        until over?(out, started)
          seqs = board(out, seqs)
          cursor = replies(out, cursor)
          pinged = ping(out) if @clock.call - pinged >= @context.ping_every
          @sleeper.call(@context.tick)
        end
      rescue Live::Unavailable => e
        # Ending the stream is the right answer: the page reconnects with
        # backoff and shows itself as reconnecting meanwhile.
        out << ": #{e.message.tr("\n", " ")}\n\n"
      end

      # @param event [String]
      # @param data [Object]
      # @param id [String, nil]
      # @return [String] one server-sent event
      def self.frame(event, data, id: nil) = "#{"id: #{id}\n" if id}event: #{event}\ndata: #{JSON.generate(data)}\n\n"

      private

      # @return [Boolean]
      def over?(out, started)
        out.closed? || @context.stopping.true? || (@context.lifetime && @clock.call - started >= @context.lifetime)
      end

      # @return [Array] the seqs now, after sending the board if they changed
      def board(out, seqs)
        board = Live.board(store: @store, keys: @keys)
        now = [board[:me], *board[:others]].compact.map { [it.dig("node", "id"), it.dig("node", "checkout"), it["seq"]] }
        out << self.class.frame("board", board) unless now == seqs
        now
      end

      # @return [String] the last reply id sent
      def replies(out, cursor)
        Live.replies(store: @store, keys: @keys, after: cursor).each do |id, reply|
          out << self.class.frame("reply", reply, id:)
          cursor = id
        end
        cursor
      end

      # @return [Float] when it pinged
      def ping(out)
        out << ": ping\n\n"
        @clock.call
      end

      # Replies already written before this page connected are not news.
      # An empty stream starts from `0-0` rather than `0`: the browser echoes
      # it back as `Last-Event-ID`, and only a full stream id is accepted.
      #
      # @return [String]
      def newest_reply = @store.xrevrange(@keys.replies, count: 1).first&.id || "0-0"
    end
  end
end

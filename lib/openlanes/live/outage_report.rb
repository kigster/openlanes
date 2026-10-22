# frozen_string_literal: true

require "json"
require "time"

module OpenLanes
  module Live
    # What the engine says once Redis is back: how long it was gone, how
    # that was measured, and which copy of the run state won.
    #
    # The duration prefers this node's last heartbeat in Redis, because it
    # is the last moment Redis provably had the engine's word. A heartbeat
    # far older than the first failure is not that: it is what an RDB
    # rollback restores, and measuring from it would overstate the outage by
    # however long the snapshot was stale. Then the engine's own monotonic
    # window is the answer, and `measured_by` says so.
    class OutageReport
      # Seconds a heartbeat may precede the first failure and still count.
      # The publisher beats every tick, so a live one is a few seconds old.
      FRESH = 15

      # @param store [#hget]
      # @param keys [OpenLanes::Live::Keys]
      # @param node [OpenLanes::Live::Node]
      # @param window [OpenLanes::Live::Outage::Window]
      # @param reconciled_from [Symbol, nil] `:redis`, `:file` or nil, from
      #   {RunRecord#reconcile}
      def initialize(store:, keys:, node:, window:, reconciled_from:)
        @store = store
        @keys = keys
        @node = node
        @window = window
        @reconciled_from = reconciled_from
      end

      # The `run.outage` wire shape (plan 022, shared with the page).
      #
      # @return [Hash]
      def to_h
        { started_at:      iso(started_at),
          ended_at:        iso(@window.ended_at),
          seconds:         seconds,
          measured_by:     measured_by,
          reconciled_from: @reconciled_from&.to_s }
      end

      # @return [String] one log line
      def line
        from = @reconciled_from ? "run state from #{@reconciled_from}" : "no run state to reconcile"
        "Redis is back after #{seconds}s (by #{measured_by}), #{from}; resuming"
      end

      # @return [Integer]
      def seconds
        (heartbeat ? @window.ended_at - heartbeat : @window.seconds).round
      end

      # @return [String] `"heartbeat"` or `"clock"`
      def measured_by = heartbeat ? "heartbeat" : "clock"

      private

      # @return [Time]
      def started_at = heartbeat || @window.started_at

      # This node's heartbeat, when it is from just before the first failure.
      #
      # @return [Time, nil]
      def heartbeat
        return @heartbeat if defined?(@heartbeat)

        @heartbeat = read_heartbeat
      end

      # @return [Time, nil]
      def read_heartbeat
        json = @store.hget(@keys.nodes, @node.name) or return nil
        at = Time.iso8601(JSON.parse(json)["heartbeat_at"].to_s)
        at if at <= @window.started_at && @window.started_at - at <= FRESH
      rescue JSON::ParserError, ArgumentError, Unavailable
        nil
      end

      # @param time [Time]
      # @return [String]
      def iso(time) = time.utc.iso8601
    end
  end
end

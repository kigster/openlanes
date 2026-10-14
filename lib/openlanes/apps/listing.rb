# frozen_string_literal: true

require "json"

module OpenLanes
  module Apps
    # The apps running on this machine, as the control room reads them from
    # Redis: one hash per machine (`Live::Keys#apps`), a field per plan, its
    # value the plan's process statuses and a heartbeat.
    #
    # Per machine rather than per checkout, because the control room runs in
    # the main checkout and an app runs in the plan's worktree; per machine
    # rather than per repository, because `127.0.0.1:11101` means nothing on
    # another one.
    #
    # A runner killed with KILL never removes its field, so a field whose
    # heartbeat is older than {TTL} is dropped by whoever reads it, the way
    # `Live.board` drops a node that stopped heartbeating.
    module Listing
      # Seconds a plan's entry outlives its last heartbeat.
      TTL = 30

      module_function

      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @param plan [String]
      # @param statuses [Array<OpenLanes::Apps::Status>]
      # @param now [Time]
      # @return [void]
      def write(store:, keys:, plan:, statuses:, now: Time.now)
        store.hset(keys.apps, plan, JSON.generate("heartbeat" => now.to_f, "processes" => statuses.map(&:to_h)))
      end

      # @return [void]
      def remove(store:, keys:, plan:) = store.hdel(keys.apps, plan)

      # Every live process, oldest plan first, in each plan's start order.
      #
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @param now [Time]
      # @return [Array<Hash>] `<app>` hashes, as {Status#to_h} wrote them
      def read(store:, keys:, now: Time.now)
        entries = store.hgetall(keys.apps).transform_values { parse(it) }
        stale = entries.select { |_, entry| entry.nil? || now.to_f - entry["heartbeat"].to_f > TTL }.keys
        store.hdel(keys.apps, *stale) unless stale.empty?
        entries.except(*stale).sort.flat_map { |_, entry| Array(entry["processes"]) }
      end

      # @return [Hash, nil] nil for a field that is not ours to read
      def parse(json)
        data = JSON.parse(json.to_s)
        data.is_a?(Hash) ? data : nil
      rescue JSON::ParserError
        nil
      end
    end
  end
end

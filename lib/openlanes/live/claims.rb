# frozen_string_literal: true

module OpenLanes
  module Live
    # The one rule that keeps machines sharing a Redis apart (W26): no two
    # nodes work the same plan.
    #
    # A claim is `SET NX EX`, renewed by the heartbeat while the run keeps
    # the plan, and released by compare-and-delete so a node can only ever
    # remove its own. A node that dies lets its claims lapse within
    # {Keys::CLAIM_TTL} seconds. This is advisory between well-behaved
    # openlanes processes, like agent-lock, not a defence (W29).
    class Claims
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @param ttl [Integer] seconds
      def initialize(store:, keys:, ttl: Keys::CLAIM_TTL)
        @store = store
        @keys = keys
        @ttl = ttl
        @held = []
        @mutex = Mutex.new
      end

      # @return [Array<String>] ordinals this node holds, as far as it knows
      def held = @mutex.synchronize { @held.dup }

      # Take the plan, or keep it if it is already ours.
      #
      # @param ordinal [#to_s]
      # @return [Boolean] whether this node holds it now
      def claim(ordinal)
        key = @keys.claim(ordinal)
        ok = @store.set(key, @keys.node, ex: @ttl, nx: true) || @store.compare_and_expire(key, @keys.node, @ttl)
        @mutex.synchronize { @held |= [ordinal.to_s] } if ok
        ok
      end

      # Extend every claim this node holds. One that lapsed and was taken by
      # another node in the meantime is dropped from {#held}, not fought for.
      #
      # One that is simply gone is taken back: a Redis that restarted empty
      # (W32) has lost every claim, and reading that as "another machine
      # took it" stopped this machine's own agents for plans nobody else
      # wanted. `SET NX` still loses to a node that got there first.
      #
      # @return [Array<String>] the ordinals lost
      def renew
        lost = held.reject do |ordinal|
          key = @keys.claim(ordinal)
          @store.compare_and_expire(key, @keys.node, @ttl) || @store.set(key, @keys.node, ex: @ttl, nx: true)
        end
        @mutex.synchronize { @held -= lost }
        lost
      end

      # @param ordinal [#to_s]
      # @return [Boolean] whether a claim of ours was removed
      def release(ordinal)
        @mutex.synchronize { @held.delete(ordinal.to_s) }
        @store.compare_and_delete(@keys.claim(ordinal), @keys.node)
      end

      # @return [void]
      def release_all = held.each { |ordinal| release(ordinal) }

      # @param ordinal [#to_s]
      # @return [String, nil] the node name holding the plan
      def held_by(ordinal) = @store.get(@keys.claim(ordinal))

      # @param ordinal [#to_s]
      # @return [Boolean] whether another node holds the plan
      def foreign?(ordinal)
        holder = held_by(ordinal)
        !holder.nil? && holder != @keys.node
      end
    end
  end
end

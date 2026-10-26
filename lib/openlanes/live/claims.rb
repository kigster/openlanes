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
        @pinned = []
        @mutex = Mutex.new
      end

      # A plan another node held when {#hold} asked for it.
      #
      # @!attribute [r] ordinal
      #   @return [String]
      # @!attribute [r] holder
      #   @return [String, nil] the holding node's name; nil when the claim
      #     lapsed between the refusal and the look
      Taken = Data.define(:ordinal, :holder)

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
        @mutex.synchronize do
          @held -= lost
          @pinned -= lost
        end
        lost
      end

      # Take every plan or none, and keep them until {#release_all}: what
      # `openlanes run 005,006` does before any agent starts (O1, O2 in
      # docs/decisions/decisions-on-factory-start-stop.md). An engine claims a
      # plan only when it starts an agent on it, so a plan the factory had in
      # its tree but was not working yet was held by nobody; holding them all
      # up front closes that gap, and the claim itself is the check, since
      # `SET NX` leaves no moment between "is it free?" and "it is mine".
      #
      # @param ordinals [Array<#to_s>]
      # @return [Array<Taken>] the plans another node held, empty when all
      #   of them are ours now; on a refusal none of them is
      def hold(ordinals)
        taken = ordinals.map(&:to_s).reject { claim(it) }
        unless taken.empty?
          (ordinals.map(&:to_s) - taken).each { release(it, pinned: true) }
          return taken.map { Taken.new(ordinal: it, holder: held_by(it)) }
        end

        @mutex.synchronize { @pinned |= ordinals.map(&:to_s) }
        []
      end

      # Give the plan up, unless {#hold} pinned it: a run that holds its
      # plans keeps them between one agent and the next, or the factory
      # would take a plan the moment its first agent finished.
      #
      # @param ordinal [#to_s]
      # @param pinned [Boolean] release it even when it is pinned
      # @return [Boolean] whether a claim of ours was removed
      def release(ordinal, pinned: false)
        return false if !pinned && @mutex.synchronize { @pinned.include?(ordinal.to_s) }

        @mutex.synchronize do
          @held.delete(ordinal.to_s)
          @pinned.delete(ordinal.to_s)
        end
        @store.compare_and_delete(@keys.claim(ordinal), @keys.node)
      end

      # Everything this node holds, pinned or not: the run is ending.
      #
      # @return [void]
      def release_all = held.each { |ordinal| release(ordinal, pinned: true) }

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

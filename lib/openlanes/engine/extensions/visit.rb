# frozen_string_literal: true

module OpenLanes
  module Engine
    class Extensions
      # One agent on one visit of a plan to a state, and which requests are
      # about it. A visit is named by the plan's `moves`, as it is for the
      # rounds themselves ({Plans::Rounds}), and round numbers start again at
      # 1 on each.
      #
      # Requests were once found by agent, state and round alone. A plan that
      # came back to a state after a rejection or an unblock then found the
      # earlier visit's request for "round 1": no new request was raised and
      # the plan parked with nobody asked, and a request left open from the
      # earlier visit was shown and answered for a grant that had expired.
      #
      # A request written before requests named their visit has no `moves`.
      # Settled, it belongs to no visit, so it neither counts as a grant nor
      # stands in for a new request; still open, it is this visit's, and
      # {Plans::PlanState#settle_extension!} stamps it when it is answered.
      #
      # @!attribute [r] agent
      #   @return [String]
      # @!attribute [r] state
      #   @return [String] the status key
      # @!attribute [r] moves
      #   @return [Integer] the plan's moves count for the visit
      Visit = Data.define(:agent, :state, :moves) do
        # @param plan [OpenLanes::Plans::PlanState]
        # @param agent [String]
        # @param state [#to_s]
        # @return [Visit] the plan's current visit to +state+
        def self.of(plan, agent, state) = new(agent:, state: state.to_s, moves: plan.moves)

        # @param all [Array<Hash>] the plan's requests
        # @return [Hash, nil] the agent's unsettled request on this visit
        def pending(all) = all.find { mine?(it) && !it.key?("settled_at") && !elsewhere?(it) }

        # A time request answered with time on the running clock does not
        # count: when that time runs low too, the round asks again, so a
        # person can add to an automatic grant.
        #
        # @param all [Array<Hash>]
        # @param round [Integer]
        # @param limit [String] "time" or "rounds"
        # @return [Boolean] whether this round of the visit already asked about this limit
        def asked?(all, round, limit)
          all.any? { here?(it) && it["round"] == round && it["limit"] == limit && it["grant"] != "live" }
        end

        # @param all [Array<Hash>]
        # @param grant [String] "live" or "round"
        # @return [Boolean] whether the visit's one grant of this kind nobody answered is spent
        def auto?(all, grant) = all.any? { here?(it) && it["by"] == AUTO && it["grant"] == grant }

        # @param all [Array<Hash>]
        # @return [Array<Hash>] the requests that gave the agent a round on this visit
        def granted(all) = all.select { here?(it) && it["grant"] == "round" }

        # @param request [Hash]
        # @return [Boolean] whether the request names a visit, and not this one
        def elsewhere?(request) = request.key?("moves") && request["moves"] != moves

        private

        def mine?(request) = request["agent"] == agent && request["state"] == state

        def here?(request) = mine?(request) && request["moves"] == moves
      end
    end
  end
end

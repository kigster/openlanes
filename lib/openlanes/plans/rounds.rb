# frozen_string_literal: true

module OpenLanes
  module Plans
    # How many rounds an agent has spent on one visit of a plan to a state,
    # read from `state.json` and nowhere else.
    #
    # The dispatcher once kept its own count in memory, so a restarted engine
    # started every agent again at round 1: the agent was told round 1, signed
    # round 1, and the settle step looked for the round it had counted itself
    # and reported `no closing ledger line`. Asking the stages instead makes
    # the round an agent is told, the round it signs and the round the board
    # shows one number, and a restart cannot lower it.
    #
    # A visit is one stay of the plan in a state, named by the plan's `moves`
    # count when it arrived ({PlanState#moves}). A plan sent back from review
    # comes back with a larger count, so it starts that state fresh.
    #
    # A stage whose status is {PlanState::FAILED_START} spent nothing (no
    # tokens, no tool call, not killed) and is not counted: its round is
    # handed out again.
    #
    # @!attribute [r] stages
    #   @return [Array<Hash>] `state.json` stages, in dispatch order
    # @!attribute [r] signatures
    #   @return [Array<Hash>] `state.json` signatures
    Rounds = Data.define(:stages, :signatures) do
      # @param plan_state [OpenLanes::Plans::PlanState]
      # @return [OpenLanes::Plans::Rounds]
      def self.from(plan_state)
        data = plan_state.read
        new(stages: data["stages"] || [], signatures: data["signatures"] || [])
      end

      # @param agent [#to_s] the agent's name
      # @param state [#to_s] the state key the visit is in
      # @param moves [Integer] the plan's moves count for the visit
      # @return [Integer] rounds spent in this visit
      def used(agent, state, moves:) = spent(agent, state, moves).size

      # @param agent [#to_s]
      # @param state [#to_s]
      # @param moves [Integer]
      # @return [Array<Hash>] the stages that spent a round in this visit
      def visit(agent, state, moves:) = spent(agent, state, moves)

      # The round to hand out next. Never lower than a round already
      # dispatched or signed in this visit, so an agent restarted after a
      # crash, or one whose signature outran its stage, is never told a
      # number it has already used.
      #
      # @param agent [#to_s]
      # @param state [#to_s]
      # @param moves [Integer]
      # @return [Integer]
      def next(agent, state, moves:)
        visit = spent(agent, state, moves)
        [visit.size, visit.map { it["round"].to_i }.max.to_i, signed(agent, visit)].max + 1
      end

      # @param agent [#to_s]
      # @param state [#to_s]
      # @param moves [Integer]
      # @param budget [Integer] the agent's rounds, extensions included
      # @return [Integer] rounds left, never below zero
      def left(agent, state, moves:, budget:) = [budget.to_i - used(agent, state, moves:), 0].max

      # @param agent [#to_s]
      # @param state [#to_s]
      # @param moves [Integer]
      # @param count [Rounds::Count] which failed starts count
      # @return [Integer] how many failed starts in a row end this visit's
      #   record for the agent, which is what the cap of three counts
      def failed_starts(agent, state, moves:, count: Rounds::Count.new) = streak(agent, state, moves, count).size

      # @param (see #failed_starts)
      # @return [Time, nil] when the latest counted failed start ended
      def last_failed_start(agent, state, moves:, count: Rounds::Count.new)
        streak(agent, state, moves, count).filter_map { instant(it["finished_at"] || it["started_at"]) }.max
      end

      private

      def mine(agent) = stages.select { it["agent"] == agent.to_s }

      # The failed starts that end the visit's record, less the excused ones,
      # which neither count nor break the run of the others.
      def streak(agent, state, moves, count)
        mine(agent).select { visit?(it, state.to_s, moves.to_i) && after?(it, count.since) }
                   .reverse.take_while { it["status"] == PlanState::FAILED_START }
                   .reject { count.except&.match?(it["note"].to_s) }
      end

      def after?(stage, since)
        return true unless since

        # Strictly after: times carry whole seconds, and a stage started in
        # the second a grant settled is the failure that grant answered.
        (at = instant(stage["started_at"])) ? at > since : false
      end

      def spent(agent, state, moves)
        mine(agent).select { it["status"] != PlanState::FAILED_START && visit?(it, state.to_s, moves.to_i) }
      end

      # A stage this release wrote says its visit. One written before names
      # `from` and the `moves` it settled at, or only `to` and `moves`: it is
      # read as the visit those imply, so an old plan's round never goes down.
      # A round that moved the plan settled one move later than it arrived.
      def visit?(stage, state, moves)
        return stage["visit"] == moves && stage["from"] == state if stage.key?("visit")

        from = stage["from"] || stage["to"]
        return false unless from == state

        settled = stage["moves"]
        settled.nil? || settled == moves || (stage["to"] && stage["to"] != from && settled == moves + 1)
      end

      # The highest round the agent signed since this visit's first stage
      # started; zero when the visit has no stage yet.
      #
      # Times are parsed, not compared as strings: ISO 8601 strings only sort
      # by time when they share an offset, and a DST change (`-07:00` against
      # `-08:00`) put a signature 40 minutes into a visit before its start.
      def signed(agent, visit)
        since = visit.filter_map { instant(it["started_at"]) }.min or return 0

        signatures.select { it["agent"] == agent.to_s && (at = instant(it["at"])) && at >= since }
                  .map { it["round"].to_i }.max.to_i
      end

      # @return [Time, nil] nil for a missing or malformed timestamp, which
      #   then neither opens a visit nor counts as signed inside one
      def instant(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end

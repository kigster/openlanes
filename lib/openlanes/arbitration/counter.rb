# frozen_string_literal: true

module OpenLanes
  module Arbitration
    # How many times a plan has been rejected toward `merge.max_rejections`
    # (M6): staff-reviewer's and verifier's `rejected` signatures, plus every
    # `passed_check/too_lenient` ruling (a pass the arbitrator turned into a
    # rejection), counted since the last `cap` ruling, so a plan sent back
    # after `go` starts a fresh count.
    #
    # Reviewers rejecting in one review round are one rejection (plan 031,
    # D10a): three reviewers on one pull request would otherwise spend the
    # whole cap in a single round.
    #
    # A rejection is skipped when an `appeal` ruling after it struck its
    # findings and left none critical: a rejection with nothing left in it
    # is not one. Derived every time, never stored: a count kept beside the
    # ledger is a second answer to one question.
    class Counter
      # A judge's note that means a rejection: `rejected`, `rejected 1/2`
      # (staff-reviewer) or `rejected: …` (the harness signing for verifier). Anchored:
      # an approving note that says "nothing to reject" is not a rejection.
      REJECTION = %r{\Arejected(?=\z|[\s:/])}i

      # @param agents [OpenLanes::Agents::Registry] the judges are the
      #   agents in the `review` and `verification` phases
      def initialize(agents:)
        @agents = agents
      end

      # @param plan [OpenLanes::Plans::Subject]
      # @return [Integer]
      def call(plan)
        rulings = Plans::PlanState.for(plan.feature.path).rulings
        since = rulings.select { it["kind"] == "cap" }.map { time(it) }.max
        current = rulings.select { since.nil? || time(it) > since }
        rejections = judged(plan).select { since.nil? || it.at > since }
        voided = voids(current, rejections)
        (rejections.size - voided) + current.count { it["kind"] == "passed_check" && it["outcome"] == "too_lenient" }
      end

      private

      # @param plan [OpenLanes::Plans::Subject]
      # @return [Array<OpenLanes::Plans::Ledger::Entry>] rejections, oldest first
      def judged(plan)
        judges = @agents.all.select { %w[review verification].include?(it.phase.to_s) }
        files = judges.flat_map(&:ledger).uniq
        names = judges.map(&:name)
        rounds = review_rounds(plan)
        Plans::Ledger.read(plan.feature.path, files).entries
                     .select { names.include?(it.agent) && it.completed? && it.note.to_s.strip.match?(REJECTION) }
                     .sort_by(&:at)
                     .uniq { |entry| rounds.fetch([entry.agent, entry.round, entry.note]) { [entry.agent, entry.note, entry.at.to_i / 60] } }
      end

      # The review round of each reviewer's verdict, from its stage in
      # `state.json`. A rejection with no such stage (verifier's, or one
      # signed before verdicts were recorded) is its own round.
      #
      # @param plan [OpenLanes::Plans::Subject]
      # @return [Hash{Array => Array}] [agent, round, note] to [:review, moves]
      def review_rounds(plan)
        Plans::PlanState.for(plan.feature.path).stages
                        .select { it["verdict"] && it["review"] }
                        .to_h { [[it["agent"], it["round"], it["verdict"]], [:review, it["review"]]] }
      end

      # Each fully struck appeal voids the latest rejection before it that
      # no earlier appeal voided.
      #
      # @param rulings [Array<Hash>]
      # @param rejections [Array<OpenLanes::Plans::Ledger::Entry>]
      # @return [Integer]
      def voids(rulings, rejections)
        void = []
        rulings.select { it["kind"] == "appeal" && it["outcome"] == "struck" && Array(it.dig("findings", "critical")).empty? }
               .each do |ruling|
                 at = time(ruling)
                 hit = rejections.each_index.select { rejections[it].at <= at && !void.include?(it) }.last
                 void << hit if hit
               end
        void.size
      end

      # @param ruling [Hash]
      # @return [Time]
      def time(ruling) = Time.iso8601(ruling["at"])
    end
  end
end

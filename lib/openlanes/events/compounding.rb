# frozen_string_literal: true

module OpenLanes
  module Events
    # Whether memory pays: reviewer rounds to a plan's first approval, for
    # runs with lessons in the prompt and for runs under `--no-memory`.
    #
    # A plan's rounds are the reviews it received up to and including its
    # first approval, and it counts on the side of the run that approved it,
    # but only when every one of those reviews came from a run on that same
    # side. A plan rejected under `--no-memory` and approved with memory on
    # is excluded: crediting either side with all of its rounds would charge
    # memory for reviews it never saw. A run recorded before `run_started`
    # carried `memory` is unknown, so a plan it reviewed is excluded too.
    class Compounding
      # The two columns, by the flag `run_started` carries.
      SIDES = { on: true, off: false }.freeze

      # @param events [Array<OpenLanes::Events::Event>] already deduplicated
      def initialize(events)
        @events = events
      end

      # @return [Hash{Symbol => Hash{Symbol => Object}}] `on` and `off`
      def call
        memory = flags
        approvals = rounds_to_approval(memory)
        SIDES.to_h do |side, flag|
          rounds = approvals.select { it[:memory] == flag }.map { it[:rounds] }.sort
          [side, { runs: memory.count { |_, on| on == flag }, approved: rounds.size, rounds_mean: mean(rounds),
                   rounds_median: median(rounds) }]
        end
      end

      private

      # @return [Hash{String => Boolean}] each run that said whether memory was on
      def flags
        started = @events.select { it.kind == "run_started" && [true, false].include?(it.payload["memory"]) }
        started.to_h { [it.run, it.payload["memory"]] }
      end

      # @param memory [Hash{String => Boolean}] {#flags}
      # @return [Array<Hash{Symbol => Object}>] `memory` and `rounds`, one per plan approved on one side alone
      def rounds_to_approval(memory)
        reviews.group_by { [it.project, it.plan] }.values.filter_map do |plan|
          first = plan.index { it.payload["verdict"] == "approved" } or next
          side = side_of(plan[..first], memory)
          { memory: side, rounds: first + 1 } unless side.nil?
        end
      end

      # @return [Array<OpenLanes::Events::Event>] every review, oldest first
      def reviews = @events.select { it.kind == "pr_reviewed" }.sort_by { [it.at.to_s, it.event_id.to_s] }

      # @param reviews [Array<OpenLanes::Events::Event>] one plan's, up to its first approval
      # @return [Boolean, nil] the one side every review came from; nil when mixed or unknown
      def side_of(reviews, memory)
        sides = reviews.map { memory[it.run] }.uniq
        sides.first if sides.size == 1
      end

      # @return [Float, nil]
      def mean(rounds) = rounds.empty? ? nil : (rounds.sum.to_f / rounds.size).round(2)

      # @return [Float, nil]
      def median(sorted)
        return nil if sorted.empty?

        mid = sorted.size / 2
        (sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0).to_f
      end
    end
  end
end

# frozen_string_literal: true

require "time"

module OpenLanes
  module Events
    # The answers the log exists for, computed from a list of events and
    # printed by nobody: `Presentation::EventsReport` renders the result.
    #
    # A unique agent run is `(plan, round, agent)`. A re-block after an
    # answer is a second block on the same run (spec, open question 6), so
    # `blocks` and `runs_needing_feedback` are kept apart on purpose.
    class Report
      # One group of usage: per run, or per adapter and model. Never summed
      # across adapters, since claude counts cache tokens into input and
      # codex does not (spec, Research contradiction 3).
      #
      # @!attribute [r] cost_usd
      #   @return [Float, nil] nil when any spend in the group was unpriced
      # @!attribute [r] estimated
      #   @return [Boolean] true when any figure in the group was an estimate
      Usage = Data.define(:run,
        :adapter,
        :model,
        :invocations,
        :input_tokens,
        :output_tokens,
        :cost_usd,
        :estimated,
        :incomplete)

      # @!attribute [r] runs
      #   @return [Integer] unique agent runs, `(plan, round, agent)`, that finished
      # @!attribute [r] completion_rate
      #   @return [Float, nil] share of those that finished `Completed`; nil with none
      # @!attribute [r] blocks
      #   @return [Integer] the questions every `block_raised` left open
      # @!attribute [r] runs_needing_feedback
      #   @return [Integer] unique agent runs with at least one block
      # @!attribute [r] intervention_rate
      #   @return [Float, nil] runs_needing_feedback over runs started; nil with none
      # @!attribute [r] time_to_answer
      #   @return [Hash{Symbol => Object}] `count`, `median_s`, `max_s`
      # @!attribute [r] pr_outcomes
      #   @return [Hash{String => Integer}] `opened`, `reviewed`, `approved`,
      #     `rejected`, `merged`, `closed`
      # @!attribute [r] usage_by_run
      #   @return [Array<Usage>]
      # @!attribute [r] usage_by_model
      #   @return [Array<Usage>]
      # @!attribute [r] skipped_lines
      #   @return [Integer]
      Result = Data.define(:runs,
        :completion_rate,
        :blocks,
        :runs_needing_feedback,
        :intervention_rate,
        :time_to_answer,
        :pr_outcomes,
        :usage_by_run,
        :usage_by_model,
        :skipped_lines) do
        # @return [Hash] JSON-ready, what `--format json` prints
        def to_h = super.merge(usage_by_run: usage_by_run.map(&:to_h), usage_by_model: usage_by_model.map(&:to_h))
      end

      # The PR kinds, as the outcome keys they count under.
      PR_KINDS = { "pr_opened" => "opened", "pr_reviewed" => "reviewed", "pr_merged" => "merged",
                   "pr_closed" => "closed" }.freeze

      # The verdicts a `pr_reviewed` carries, counted under their own keys.
      VERDICTS = %w[approved rejected].freeze

      # @param events [Array<OpenLanes::Events::Event>] already deduplicated
      # @param skipped_lines [Integer]
      def initialize(events, skipped_lines: 0)
        @events = events
        @skipped_lines = skipped_lines
      end

      # @return [Result]
      def call
        finished = by_run(of("agent_finished"))
        started = by_run(of("agent_started")).keys | finished.keys
        blocked = of("block_raised").sort_by { Time.iso8601(it.at) }
        feedback = blocked.map { run_key(it) }.uniq.size
        Result.new(runs: finished.size,
          completion_rate: rate(finished.values.count { it.payload["status"] == "Completed" }, finished.size),
          blocks: blocked.sum { questions(it) },
          runs_needing_feedback: feedback,
          intervention_rate: rate(feedback, started.size),
          time_to_answer: time_to_answer(blocked),
          pr_outcomes: pr_outcomes,
          usage_by_run: usage(finished.values, &:run),
          usage_by_model: usage(finished.values) { nil },
          skipped_lines: @skipped_lines)
      end

      private

      # @return [Array<OpenLanes::Events::Event>]
      def of(kind) = @events.select { it.kind == kind }

      # @return [Array] the unique agent run an event belongs to
      def run_key(event) = [event.plan, event.payload["round"], event.agent]

      # The last event per unique run: a restarted invocation finishing
      # again replaces the first, so one run counts once.
      #
      # @return [Hash{Array => OpenLanes::Events::Event}]
      def by_run(events) = events.to_h { [run_key(it), it] }

      # @return [Float, nil]
      def rate(part, whole) = whole.zero? ? nil : (part.to_f / whole).round(4)

      # One `block_raised` is one Blocked signing, and the questions it
      # left open are in its payload. Counting events instead made `blocks`
      # equal the run count whenever an agent asked several questions at
      # once. An event with no count still stands for one block.
      #
      # @return [Integer]
      def questions(block) = [block.payload["blocks"].to_i, 1].max

      # Each question of a block is paired with the first answer on the
      # same plan that came after it; an answer is used once. By plan, not
      # by run: the unblocker drains a plan's questions and does not know
      # which agent's round asked them, and a blocked plan runs no other
      # agent meanwhile.
      #
      # @return [Hash{Symbol => Object}]
      def time_to_answer(blocked)
        answers = of("human_answered").sort_by { stamp(it) }.group_by(&:plan)
        waits = blocked.flat_map do |block|
          raised = Time.iso8601(block.at)
          pool = answers.fetch(block.plan, [])
          pool.select { stamp(it) >= raised }.first(questions(block)).map do |answer|
            pool.delete(answer)
            stamp(answer) - raised
          end
        end.sort
        { count: waits.size, median_s: median(waits), max_s: waits.last&.round(1) }
      end

      # @return [Time]
      def stamp(answer) = Time.iso8601(answer.payload["answered_at"] || answer.at)

      # @return [Float, nil]
      def median(sorted)
        return nil if sorted.empty?

        mid = sorted.size / 2
        (sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0).round(1)
      end

      # Each PR counts once per outcome, whatever re-asked the watch, and
      # once per verdict: a PR rejected and later approved is one of each.
      #
      # @return [Hash{String => Integer}]
      def pr_outcomes
        counts = PR_KINDS.to_h { |kind, key| [key, prs(of(kind))] }
        reviews = of("pr_reviewed")
        verdicts = VERDICTS.to_h { |verdict| [verdict, prs(reviews.select { it.payload["verdict"] == verdict })] }
        counts.slice("opened", "reviewed").merge(verdicts, counts.slice("merged", "closed"))
      end

      # @return [Integer] the distinct pull requests among +events+
      def prs(events) = events.map { [it.project, it.plan, it.payload["number"]] }.uniq.size

      # @return [Array<Usage>]
      def usage(finished, &run)
        finished.group_by { [run.call(it), it.adapter, it.model] }.map do |(run_id, adapter, model), group|
          costs = group.map { it.payload["cost_usd"] }
          Usage.new(run: run_id,
            adapter:,
            model:,
            invocations: group.size,
            input_tokens: group.sum { it.payload["input_tokens"].to_i },
            output_tokens: group.sum { it.payload["output_tokens"].to_i },
            cost_usd: costs.any?(&:nil?) ? nil : costs.sum.round(6),
            estimated: group.any? { it.payload["estimated"] },
            incomplete: group.any? { it.payload["incomplete"] })
        end.sort_by { [it.run.to_s, it.adapter.to_s, it.model.to_s] }
      end
    end
  end
end

# frozen_string_literal: true

require "json"

module OpenLanes
  module Presentation
    # `openlanes events report`, drawn: the aggregates {Events::Report}
    # computed from the durable log, as a table or as JSON.
    #
    # Returns strings and prints nothing, so the caller decides whether they
    # go to STDOUT or to a file.
    class EventsReport
      # What a cost the log could not price reads as. Never `$0`: a codex or
      # pi run that cost nothing and one that was not priced are different facts.
      UNKNOWN = "unknown"

      # @param result [OpenLanes::Events::Report::Result]
      def initialize(result)
        @result = result
      end

      # @param format [Symbol, String] `:table` or `:json`
      # @return [String]
      def render(format: :table) = format.to_s == "json" ? json : table

      # @param cost [Float, nil]
      # @param estimated [Boolean]
      # @return [String] `unknown` for nil, and an `(est.)` label on a computed figure
      def self.money(cost, estimated: false)
        return UNKNOWN if cost.nil?

        format("$%.2f", cost) + (estimated ? " (est.)" : "")
      end

      # @param value [Float, nil]
      # @return [String]
      def self.percent(value) = value.nil? ? "n/a" : format("%.1f%%", value * 100)

      private

      attr_reader :result

      # @return [String]
      def json = "#{JSON.pretty_generate(result.to_h)}\n"

      # @return [String]
      def table
        lines = ["Runs", *summary, "", "PR outcomes", *pr_lines, "", "Usage by adapter and model", *usage(result.usage_by_model),
                 "", "Usage by run", *usage(result.usage_by_run)]
        lines.push("", "#{result.skipped_lines} unreadable line(s) skipped") if result.skipped_lines.positive?
        "#{lines.join("\n")}\n"
      end

      # @return [Array<String>]
      def summary
        wait = result.time_to_answer
        [
          "  agent runs finished     #{result.runs}",
          "  completion rate         #{self.class.percent(result.completion_rate)}",
          "  blocks                  #{result.blocks} over #{result.runs_needing_feedback} unique run(s)",
          "  intervention rate       #{self.class.percent(result.intervention_rate)}",
          "  time to answer          #{answer_time(wait)}"
        ]
      end

      # @return [String]
      def answer_time(wait)
        return "no answered blocks" if wait[:count].to_i.zero?

        "#{wait[:count]} answered, median #{wait[:median_s]}s, max #{wait[:max_s]}s"
      end

      # @return [Array<String>]
      def pr_lines = result.pr_outcomes.map { |name, count| "  #{name.ljust(10)} #{count}" }

      # Never summed across adapters: claude counts cache tokens into input
      # and codex does not, so a total would compare unlike numbers.
      #
      # @return [Array<String>]
      def usage(rows)
        return ["  none"] if rows.empty?

        rows.map do |row|
          label = [row.run, row.adapter, row.model].compact.join(" / ")
          note = row.incomplete ? "  (incomplete: sub-agents not counted)" : ""
          "  #{label}: #{row.invocations} invocation(s), #{row.input_tokens} in, #{row.output_tokens} out, " \
            "#{self.class.money(row.cost_usd, estimated: row.estimated)}#{note}"
        end
      end
    end
  end
end

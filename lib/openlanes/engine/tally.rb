# frozen_string_literal: true

module OpenLanes
  module Engine
    # What a `run` cost, once it is over.
    #
    # The loop reports movement — which plan went from ⭐ to 🟡, which agent
    # failed and why — and says nothing about the bill. A round of five agents
    # against a large repository spends several million tokens and the better
    # part of an hour, and until this existed the only record of that was a
    # directory of trace files nobody reads.
    #
    # {#render} returns a string and prints nothing, so the caller decides where
    # it goes, the same way {Reporter} works.
    class Tally
      # One agent's share of the run, added up across every round it ran in.
      #
      # @!attribute [r] name
      #   @return [String]
      # @!attribute [r] invocations
      #   @return [Integer] times this agent was started
      # @!attribute [r] subagents
      #   @return [Integer] sub-agents it spawned, across all of them
      # @!attribute [r] up
      #   @return [Integer] tokens sent, sub-agent spend included
      # @!attribute [r] down
      #   @return [Integer] tokens generated
      # @!attribute [r] seconds
      #   @return [Float] how long it was running, added up
      Row = Data.define(:name, :invocations, :subagents, :up, :down, :seconds)

      # Cells per column, so the header, the rows and the rule cannot drift.
      WIDTHS = { name: 22, invocations: 6, subagents: 11, up: 9, down: 9, seconds: 8 }.freeze

      # @param attempts [Array<OpenLanes::Engine::Runner::Attempt>]
      # @param seconds [Float] wall clock for the whole loop, which is not the
      #   sum of the agents' own times: several of them run at once
      # @param rounds [Integer, nil] accepted so an older caller still works, and
      #   otherwise unused: the loop has no rounds of its own any more, each
      #   agent counts its own per plan, so the summary counts invocations
      def initialize(attempts:, seconds:, rounds: nil)
        @attempts = attempts.reject { |a| a.ordinal == "?" }
        @seconds = seconds
        @rounds = rounds
      end

      # @return [Array<OpenLanes::Engine::Runner::Attempt>]
      attr_reader :attempts

      # @return [Float] wall clock
      attr_reader :seconds

      # @return [Integer, nil]
      attr_reader :rounds

      # Plans an agent was actually started against, counted once each however
      # many rounds they took.
      #
      # @return [Integer]
      def plans = attempts.map(&:ordinal).uniq.size

      # @return [Integer] tokens sent, everything included
      def up = attempts.sum(&:up)

      # @return [Integer] tokens generated
      def down = attempts.sum(&:down)

      # @return [Integer] sub-agents spawned by every agent in the run
      def subagents = attempts.sum(&:subagents)

      # Sub-agent spend that arrived as one number. `claude` reports what a
      # sub-agent cost without splitting it between the two directions, so this
      # much of {#up} is really up and down together.
      #
      # @return [Integer]
      def delegated = attempts.sum(&:delegated)

      # @return [Float] seconds of agent time, added up across all of them
      def busy = attempts.sum(&:seconds)

      # How many agents were running at any given moment, averaged over the
      # run: agent-seconds divided by wall-clock seconds. Below the `-j` ceiling
      # by however much the round spent waiting for its slowest member.
      #
      # @return [Float]
      def concurrency = seconds.positive? ? busy / seconds : 0.0

      # @return [Array<OpenLanes::Engine::Tally::Row>] one per agent, dearest first
      def by_agent
        attempts.group_by(&:agent).map { |name, list|
          Row.new(name:,
            invocations: list.size,
            subagents: list.sum(&:subagents),
            up: list.sum(&:up),
            down: list.sum(&:down),
            seconds: list.sum(&:seconds))
        }.sort_by { |row| -row.up }
      end

      # @return [String] the table and the summary line under it
      def render
        return summary if attempts.empty?

        ([header, rule] + by_agent.map { |row| line(row) } + [rule, totals, "", summary]).join("\n")
      end

      # @return [String] the one-line version, for a box
      def summary
        [
          "#{plans} plan#{"s" unless plans == 1} addressed",
          "#{attempts.size} invocation#{"s" unless attempts.size == 1}",
          duration(seconds),
          "#{format("%.1f", concurrency)} agents at a time",
          "↑ #{UI.abbreviate(up)} ↓ #{UI.abbreviate(down)}"
        ].join(" · ") + delegation
      end

      private

      # @return [String] the caveat, where there is one to make
      def delegation
        return "" if delegated.zero?

        "\n#{subagents} sub-agent#{"s" unless subagents == 1} reported #{UI.abbreviate(delegated)} " \
          "tokens without splitting them, counted above as ↑."
      end

      # @return [String]
      def header
        cell("Agent", :name) + %i[invocations subagents up down seconds]
                               .zip(["runs", "sub-agents", "↑", "↓", "time"])
                               .map { |key, text| right(text, key) }.join
      end

      # @return [String]
      def rule = WIDTHS.values.map { |width| ("─" * (width - 1)) + " " }.join

      # @param row [OpenLanes::Engine::Tally::Row]
      # @return [String]
      def line(row)
        cell(row.name, :name) + right(row.invocations.to_s, :invocations) +
          right(row.subagents.to_s, :subagents) + right(UI.abbreviate(row.up), :up) +
          right(UI.abbreviate(row.down), :down) + right(duration(row.seconds), :seconds)
      end

      # @return [String]
      def totals
        cell("", :name) + right(attempts.size.to_s, :invocations) + right(subagents.to_s, :subagents) +
          right(UI.abbreviate(up), :up) + right(UI.abbreviate(down), :down) + right(duration(busy), :seconds)
      end

      # @param text [String]
      # @param key [Symbol]
      # @return [String] padded to its column, left-justified
      def cell(text, key) = UI.fit(text, WIDTHS.fetch(key))

      # @param text [String]
      # @param key [Symbol]
      # @return [String] padded to its column, right-justified
      def right(text, key)
        width = WIDTHS.fetch(key) - 1
        text = UI.fit(text, width).rstrip
        UI.fit("", width - UI.display_width(text)) + text + " "
      end

      # @param seconds [Numeric]
      # @return [String] e.g. "42s", "12m40s", "1h04m"
      def duration(seconds)
        total = seconds.to_i
        return "#{total}s" if total < 60
        return "#{total / 60}m#{format("%02ds", total % 60)}" if total < 3600

        "#{total / 3600}h#{format("%02dm", (total % 3600) / 60)}"
      end
    end
  end
end

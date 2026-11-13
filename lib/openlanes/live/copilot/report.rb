# frozen_string_literal: true

require "json"

module OpenLanes
  module Live
    class Copilot
      # The answer to `/status`, `/status NNN` and `/stats` (plan 069.00),
      # read from the snapshot the engine writes to Redis every tick. It
      # reads and never writes, so a question can never become a command.
      class Report
        # The answer when no engine has written a snapshot yet.
        NOTHING = "No engine is running on this node, so there are no figures yet."

        # @param snapshot [String, nil] the snapshot's JSON, as Redis holds it
        def initialize(snapshot)
          @snapshot = snapshot && JSON.parse(snapshot)
        rescue JSON::ParserError
          @snapshot = nil
        end

        # @param query [OpenLanes::Live::Copilot::Slash::Query]
        # @return [String]
        def call(query)
          return NOTHING unless @snapshot
          return stats if query.kind == "stats"

          query.plan ? plan(query.plan) : board
        end

        private

        # @return [Array<Hash>]
        def plans = Array(@snapshot["plans"])

        # @return [String]
        def board
          return "No plan is on the board." if plans.empty?

          (["#{plans.size} plan#{"s" unless plans.size == 1} on the board:"] + plans.map { line(it) }).join("\n")
        end

        # @param ordinal [String]
        # @return [String]
        def plan(ordinal)
          found = plans.find { it["ordinal"] == ordinal } or return "#{ordinal} is not on the board."

          cars = Array(found["cars"])
          agents = cars.empty? ? ["  no agent is working on it"] : cars.map { car(it) }
          ([line(found)] + agents).join("\n")
        end

        # @param plan [Hash]
        # @return [String]
        def line(plan)
          status = plan["status"] || {}
          agents = Array(plan["cars"]).map { it["agent"] }
          "#{plan["ordinal"]} #{status["emoji"]} #{status["label"]} · #{plan["title"]}" \
            "#{" · #{agents.join(", ")}" unless agents.empty?} · $#{money(plan["cost"])}"
        end

        # @param car [Hash]
        # @return [String]
        def car(car)
          "  #{car["agent"]}: #{car["state"]}, round #{car["round"]}, #{car["model"]}" \
            "#{", #{car["remaining"]}s left" if car["remaining"]}#{" · #{car["message"]}" unless car["message"].to_s.empty?}"
        end

        # @return [String]
        def stats
          run = @snapshot["run"] || {}
          ["Run #{run["status"]}#{", since #{run["started_at"]}" if run["started_at"]}",
           "agents working: #{run["agents_working"].to_i} of #{run["jobs"].to_i}",
           "plans on the board: #{plans.size}",
           "tokens: #{run["up"].to_i} in, #{run["down"].to_i} out",
           "cost: $#{money(run["cost"])}"].join("\n")
        end

        # @param value [Numeric, nil]
        # @return [String]
        def money(value) = format("%.2f", value.to_f)
      end
    end
  end
end

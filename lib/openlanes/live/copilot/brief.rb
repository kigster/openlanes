# frozen_string_literal: true

module OpenLanes
  module Live
    class Copilot
      # What c3po-operator is told with each message: the board as it stands,
      # where to read further, and the person's words.
      #
      # The board lives in Redis, which the agent cannot read: its Bash runs
      # only `openlanes` commands that read state, and none of them prints the
      # live board. So the server reads the snapshot and writes it in here,
      # fresh with every message, since the run moves between two questions.
      # It is written as lines rather than the snapshot's JSON because the
      # agent pays for every token of it on every message.
      class Brief
        # Recent log lines carried.
        LOG_LINES = 20

        # Characters of a question's body carried; the agent reads the rest
        # from blocked.md when it needs it.
        BODY = 400

        # @param text [String] what the person typed
        # @param board [Hash, nil] this node's `Snapshot` as parsed JSON
        # @param others [Array<Hash>] other machines' snapshots
        # @param plans_dir [String]
        # @param trace_dir [String]
        def initialize(text:, board:, plans_dir:, trace_dir:, others: [])
          @text = text
          @board = board
          @others = others
          @plans_dir = plans_dir
          @trace_dir = trace_dir
        end

        # @return [String]
        def to_s
          [board, others, where, "## The person says\n\n#{@text}"].compact.join("\n\n")
        end

        private

        # @return [String]
        def board
          return "## The board\n\nNo engine is publishing a board for this checkout: no run is going, or it has ended." unless @board

          run = @board["run"] || {}
          lines = ["## The board at #{@board["at"]}",
                   "",
                   "Run #{run["status"]}, #{run["agents_working"].to_i} agents working, ↑ #{run["up"].to_i} ↓ #{run["down"].to_i} tokens, " \
                   "$#{format("%.2f", run["cost"].to_f)}."]
          plans = Array(@board["plans"])
          lines << (plans.empty? ? "No plans on this machine's board." : "")
          plans.each { lines.concat(plan(it)) }
          backlog = Array(@board["backlog"])
          lines << "Backlog: #{backlog.map { "#{it["ordinal"]} #{it["title"]} (#{it.dig("status", "label")})" }.join("; ")}" unless backlog.empty?
          lines.concat(log)
          lines.join("\n")
        end

        # @param plan [Hash]
        # @return [Array<String>]
        def plan(plan)
          lines = ["- #{plan["ordinal"]} #{plan["title"]}: #{plan.dig("status", "emoji")} #{plan.dig("status", "label")}, " \
                   "#{plan["lane"]} lane, #{minutes(plan["elapsed"])} worked, $#{format("%.2f", plan["cost"].to_f)}" \
                   "#{", PR ##{plan.dig("pr", "number")} #{plan.dig("pr", "state")}" if plan["pr"]}"]
          Array(plan["cars"]).each { lines << car(it) }
          Array(plan["questions"]).each { lines << question(it) }
          if (stop = plan["interrupted"])
            lines << "  - interrupted: #{stop["agent"]} at #{stop["at"]}: #{stop["note"]}"
          end
          lines
        end

        # @param car [Hash]
        # @return [String]
        def car(car)
          "  - car #{car["key"]}: #{car["state"]}#{", #{car["phase"]}" if car["phase"]}, round #{car["round"]}/#{car["rounds"]}, " \
            "#{car["model"]}, ↑ #{car["up"].to_i} ↓ #{car["down"].to_i}, #{minutes(car["elapsed"])} elapsed" \
            "#{", #{minutes(car["remaining"])} left" if car["remaining"]}#{", held" if car["held"]}: #{car["message"].to_s.inspect}"
        end

        # @param question [Hash]
        # @return [String]
        def question(question)
          body = question["body"].to_s.gsub(/\s+/, " ").strip
          body = "#{body[0, BODY]}…" if body.length > BODY
          "  - question #{question["id"]} (#{question["owner"]}, asked by #{question["agent"] || "unknown"}" \
            "#{", held" if question["held"]}): #{question["heading"]}: #{body}"
        end

        # @return [Array<String>]
        def log
          lines = Array(@board["log"]).last(LOG_LINES)
          return [] if lines.empty?

          ["", "Recent log, newest last:"] + lines.map { "  #{it["at"]} #{it["source"]} #{it["level"]}: #{it["text"]}" }
        end

        # @return [String, nil]
        def others
          return nil if @others.empty?

          machines = @others.map do |snapshot|
            node = snapshot["node"] || {}
            plans = Array(snapshot["plans"]).map { "#{it["ordinal"]} #{it.dig("status", "label")}" }
            "- #{node["user"]}@#{node["host"]}: #{plans.empty? ? "no plans" : plans.join(", ")}"
          end
          "## Other machines (read only)\n\n#{machines.join("\n")}"
        end

        # @return [String]
        def where
          <<~TEXT.strip
            ## Where to read more

            - Plan folders: #{@plans_dir}. Each holds spec.md, plan.md, blocked.md when blocked, and state.json with its signatures and mailbox.
            - Agents' transcripts: #{@trace_dir}, one NDJSON file per invocation, named by time, plan and agent.
          TEXT
        end

        # @param seconds [Numeric, nil]
        # @return [String]
        def minutes(seconds) = "#{(seconds.to_f / 60).round}m"
      end
    end
  end
end

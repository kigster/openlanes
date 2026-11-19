# frozen_string_literal: true

require "socket"

module OpenLanes
  module Plans
    class PlanState
      # What a restarted run reads back: whether an agent's next round may
      # carry on its last session (M1), and the stages a dead harness left.
      class Recovery < Section
        # @return [Boolean] whether a process +pid+ (an Integer, or nil) is running
        def self.alive?(pid)
          return false unless pid.is_a?(Integer) && pid.positive?

          Process.kill(0, pid)
          true
        rescue Errno::ESRCH
          false
        rescue Errno::EPERM
          true
        end

        # The latest stage of +agent+ that names a session is the candidate:
        # resumable only when it settled leaving the plan in +state+, nothing
        # moved the plan since, it ran in +root+, and on the same adapter.
        #
        # @param agent [String]
        # @param state [#to_s]
        # @param root [String]
        # @param adapter [#to_s, nil]
        # @return [OpenLanes::Plans::PlanState::Resumption]
        def resumption(agent, state, root, adapter)
          data = read
          last = candidate(data["stages"], agent)
          return Resumption.new(session: nil, reason: "no session recorded for #{agent}") unless last

          state = state.to_s
          reason = moved(data, last, state) || elsewhere(last, root, adapter)
          Resumption.new(session: reason ? nil : last["session"],
            reason: reason || "round #{last["round"]} left it in #{state}")
        end

        # Stages a dead harness left Started, as only older releases wrote them.
        # @param alive [#call] pid → Boolean
        # @param pid [Integer] this run, which is never its own crash
        # @return [Array<Hash>]
        def stranded(alive, pid)
          read["stages"].select do |s|
            run = s["run"] || {}
            s["status"] == "Started" && run["pid"] != pid && run["host"] == Socket.gethostname && !alive.call(run["pid"])
          end
        end

        private

        # @return [Hash, nil] the latest stage naming a session; on a tie in
        #   `started_at` (second precision), the one dispatched later
        def candidate(all, agent)
          last, = all.each_with_index
                     .select { |s, _| s["agent"] == agent && !s["session"].to_s.empty? }
                     .max_by { |s, i| [started(s), i] }
          last
        end

        # @return [String, nil] why the plan is not where +last+ left it
        def moved(data, last, state)
          tag = "round #{last["round"]} (#{last["session"]})"
          if last["to"].to_s.empty? then "#{tag} never settled"
          elsif last["to"] != state then "the plan moved to #{last["to"]} after #{tag}"
          elsif (moved = moved_since(data["stages"], last, state)) then "the plan moved to #{moved} since #{tag}"
          elsif last.key?("moves") && data["moves"].to_i != last["moves"]
            "the plan moved away and back since #{tag}"
          end
        end

        # @return [String, nil] why the session cannot be resumed from here
        def elsewhere(last, root, adapter)
          session = last["session"]
          if File.expand_path(last["cwd"].to_s) != File.expand_path(root) || last["cwd"].to_s.empty?
            "session #{session} ran in #{last["cwd"] || "an unrecorded checkout"}, not #{root}"
          elsif adapter && last["adapter"] && last["adapter"] != adapter.to_s
            "session #{session} ran on #{last["adapter"]}, not #{adapter}"
          end
        end

        def started(stage) = parse_time(stage["started_at"])

        # @return [String, nil] a state some later stage left the plan in, other than +state+
        def moved_since(all, since, state)
          after = started(since)
          at = all.index { it.equal?(since) }
          all.each_with_index
             .select { |s, i| i > at || started(s) > after }
             .map { |s, _| s["to"].to_s }
             .find { !it.empty? && it != state }
        end
      end
    end
  end
end

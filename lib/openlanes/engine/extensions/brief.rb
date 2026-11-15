# frozen_string_literal: true

module OpenLanes
  module Engine
    class Extensions
      # The words the {Ladder} puts to an agent and to the arbitrator (E2).
      #
      # The arbitrator has no write tool and reads no clock, so everything
      # it rules on is in its brief: who asks, how long it has run, what it
      # asked for and why, and the most that may be granted.
      module Brief
        module_function

        # @param round [Round]
        # @param request [Hash] the request at its arbitration stage
        # @return [String] what the arbitrator is told on top of its definition
        def for(round, request)
          ["Trigger: extension", "Plan folder: #{round.subject.feature.path}", *asker(round), *asking(round, request)].join("\n")
        end

        # @param round [Round]
        # @return [String] the line in the agent's control file; its prompt holds the command
        def question(round)
          "#{Execution::Control::ESTIMATE}: about #{minutes(round.handle.remaining)} minutes left. " \
            "Say how many more you need with `openlanes state estimate`, and keep working."
        end

        # @param seconds [Numeric, nil]
        # @return [Integer]
        def minutes(seconds) = (seconds.to_i / 60.0).round

        # @return [Array<String>] who asks, and how long it has run
        def asker(round)
          job = round.job
          used = minutes(UI.monotonic - job.started_at.to_f)
          ["Raised by: #{round.agent.name}, round #{job.task.round} on #{job.state}",
           "Time used: #{used} minutes, #{minutes(round.auto_granted)} of them added by the engine on its own"]
        end

        # @return [Array<String>] what it asks for, why, and the most it may be given
        def asking(round, request)
          ["Asks for: #{minutes(request["estimate"])} more minutes",
           ("Says: #{request["why"]}" if request["why"]),
           "Most you may grant: #{minutes(round.agent.extension_ceiling)} minutes"].compact
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # Each agent's rounds on each plan, kept in the {Registers}' history
        # under its mutex, since the page's commands reach it too.
        class Rounds
          # @param registers [Registers]
          def initialize(registers)
            @registers = registers
          end

          # Hand back the round an interrupted agent lost, so a person's
          # "resume" starts it again even when it had no rounds left.
          #
          # @param ordinal [#to_s]
          # @param agent [String]
          # @return [Boolean] whether there was an interrupted round to hand back
          def resume(ordinal, agent)
            synchronize do
              entries = history[[ordinal.to_s, agent.to_s]]
              last = entries.rindex { |h| h[:status] == "Interrupted" } or next false
              entries.delete_at(last)
              true
            end
          end

          # One entry per round: the Started written at dispatch is
          # overwritten by the outcome rather than joined by it. Two entries a
          # round would spend an agent's rounds at double speed and number
          # them 1, 3, 5.
          #
          # @return [void]
          def remember(ordinal, agent, state, status, round) # rubocop:disable Metrics/ParameterLists -- Desk's contract, called positionally by the steps
            synchronize do
              entries = history[[ordinal.to_s, agent]]
              entry = entries.find { |h| h[:state] == state && h[:round] == round }
              entry ? entry[:status] = status : entries << { state:, status:, round: }
            end
          end

          # A requeued agent's round is handed back: the stop was a person's
          # choice, not the agent running out of turns.
          #
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [void]
          def forget_round(job)
            ordinal = job.task.subject.feature.ordinal.to_s
            synchronize do
              history[[ordinal, job.task.agent.name]].reject! { |h| h[:state] == job.state && h[:round] == job.task.round }
            end
            @registers.finished_plans.delete(ordinal)
          end

          private

          def history = @registers.history

          def synchronize(&) = @registers.mutex.synchronize(&)
        end
      end
    end
  end
end

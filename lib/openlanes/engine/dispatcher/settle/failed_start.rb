# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # A start that spent nothing costs the agent no round (plan 065.00):
        # the round is handed back, and its stage is written as a failed
        # start so the log and `state.json` still show it happened.
        class FailedStart < Step
          # @return [Boolean] whether the CLI failed before the agent spent
          #   anything; a fake executor's result that cannot say is not one
          def match?(result) = result.respond_to?(:failed_start?) && result.failed_start?

          # A round that spent something proves its CLI is signed in, so the
          # next pause on that CLI starts short again.
          #
          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [void]
          def note(job)
            cli_pause.clear(adapter_for(job).name) unless match?(job.result)
          end

          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @param base [OpenLanes::Engine::Runner::Attempt]
          # @return [OpenLanes::Engine::Runner::Attempt, nil] nil for a round
          #   that was not a failed start
          def call(job, base)
            result = job.result
            return nil unless match?(result)

            forget_round(job)
            # A CLI that cannot log in fails every agent started on it the same
            # way, so it is held until a probe says it is signed in again.
            cli_pause.pause(adapter_for(job).name, result.auth_reason) if result.auth_failure?
            base.with(ok: false, status: Plans::PlanState::FAILED_START, note: "failed start: #{result.note}")
          end
        end
      end
    end
  end
end

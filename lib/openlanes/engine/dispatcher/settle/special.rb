# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Settle < Step
        # Rounds settled before anything reads the ledger: a sweep's or a
        # rebase's resolution signs nothing, so whatever the ledger holds is
        # the plan's previous round, and a crash or an app that never came up
        # has no closing line to read.
        class Special < Step
          # @param desk [Desk]
          # @param stops [Stops]
          # @param replacement [Replacement]
          def initialize(desk, stops:, replacement:)
            super(desk)
            @stops = stops
            @replacement = replacement
          end

          # @return [OpenLanes::Engine::Runner::Attempt, nil] nil when the round is an ordinary one
          def call(job, base)
            result = job.result
            return swept(job, base, result) if job.sweep
            return rebased(base, result) if job.rebase
            return @replacement.call(job, @stops.crashed(job, base, result), result) if result.is_a?(Exception)

            app_did_not_start(job, base, result) if result.is_a?(Verification::AppSession::Failed)
          end

          private

          def rebased(base, result) = result.is_a?(Exception) ? base.with(ok: false, note: "rebase: #{result.message}") : base

          # A sweep's resolution ended (U3); the keeper says what follows.
          def swept(job, base, result)
            conflict = job.sweep
            report = runner.upkeep.finished(conflict, job.task.checkout, result, held: rebases.hold(conflict.ordinal))
            base.with(**report.to_h.compact)
          end

          # The app did not come up, so verifier never ran: rejected all the
          # same (M1), with the failing process's last lines.
          def app_did_not_start(job, base, result)
            task = job.task
            subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
            remember(plan_of(job), task.agent.name, job.state, "Completed", task.round)
            rejected(job, base, result, runner.verification.reject(task, subject, why: result.to_markdown))
          end

          def rejected(job, base, result, rejection)
            base.with(ok: !rejection.nil?,
              status: "Completed",
              to: rejection&.to || job.state,
              note: "#{result.headline}; #{rejection&.note || "no open pull request to reject"}")
          end
        end
      end
    end
  end
end

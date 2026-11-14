# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rename < Step
        # staff-reviewer approved. Into 🧪 when the run verifies and the pull
        # request carries a verdict that goes on to verification; otherwise the
        # plan is finished at 👀, as it was before verifier existed. A 🔴 or,
        # under `standard`, a 🟡 after the hand-off is the hand-off's own
        # send-back, signed as one so the ledger does not call a return to 🟡
        # "approved".
        class Approval < Step
          # @param round [Completed]
          # @return [OpenLanes::Engine::Runner::Attempt]
          def call(round)
            record(round)
            said = runner.verification&.hand_off(round.subject)
            now = fresh_by(round.ordinal)&.status&.key
            return sent_on(round.base, now, said) if %i[verifying rejected building].include?(now)

            awaiting_merge(round, said)
          end

          private

          def awaiting_merge(round, said)
            finished_plans << round.ordinal
            finish(round.subject, "approved")
            round.base.with(status: "Completed", note: "#{round.base.note}; approved, awaiting merge#{"; #{said}" if said}")
          end

          def sent_on(base, now, said)
            word = now == :verifying ? "approved" : "sent back"
            base.with(status: "Completed", to: now, note: "#{base.note}; #{word}, #{said}")
          end

          # The approval goes into the event log as the `pr_reviewed` a
          # person's rejection is recorded as, or the report would count
          # reviews from rejections alone. Keyed by the round, so a PR approved
          # again after a fix cycle is a second review, and a restarted round
          # noticing the same signing is not. A plan with no open pull request
          # has nothing to count it against.
          def record(round)
            pull = round.subject.pull_requests.find(&:open?) or return
            number = pull.number.to_s.delete("#").to_i
            runner.events.record(:pr_reviewed,
              plan:    round.ordinal,
              seq:     [number, "approved", round.job.task.round],
              once:    true,
              number:,
              verdict: "approved")
          end
        end
      end
    end
  end
end

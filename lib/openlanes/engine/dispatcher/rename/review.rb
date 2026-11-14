# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rename < Step
        # A reviewer's verdict, counted with the rest of its round (plan 031,
        # D4 to D7). The verdict goes on the reviewer's stage first, so a
        # restart still counts it; the pull request is labelled only once the
        # last reviewer has spoken, and only by the engine.
        class Review < Step
          # @param desk [Desk]
          # @param advance [Advance] takes the round on once the reviewers ruled
          def initialize(desk, advance:)
            super(desk)
            @advance = advance
          end

          # @param round [Completed]
          # @return [OpenLanes::Engine::Runner::Attempt]
          def call(round)
            base = round.base
            decision = decided(round) or return unvoted(round.job, base)
            return base.with(status: "Completed", note: "#{base.note}; #{decision.note}") if decision.pending?

            @advance.call(round.with(base: base.with(note: "#{base.note}; #{decision.note}")), decision.target)
          end

          private

          # @return [OpenLanes::Engine::Reviews::Decision, nil] nil when the note reports no verdict
          def decided(round)
            reviews = runner.reviews
            note = round.entry.note.to_s
            decision = reviews.decide(round.subject, round.agent, note, running: others(round.job)) or return

            reviews.vote!(round.subject, round.agent, round.job.task.round, note)
            settled(round.subject, decision)
          end

          # A round with reviewers still to speak pauses the pull request; a
          # complete one is concluded.
          def settled(subject, decision)
            reviews = runner.reviews
            decision.pending? ? reviews.paused(subject, decision) : reviews.conclude(subject, decision)
          end

          # The other agents still in the plan, by name.
          def others(job) = running.reject { it.equal?(job) }.select { plan_of(it) == plan_of(job) }.map { it.task.agent.name }

          # A reviewer signed Completed without a verdict. Moving the plan on
          # that once took silence for approval; the round fails instead, so
          # the reviewer runs again while it has rounds left.
          def unvoted(job, base)
            remember(plan_of(job), job.task.agent.name, job.state, "Interrupted", job.task.round)
            base.with(ok: false, status: "Interrupted", note: "#{base.note}; signed no verdict: great, passed, rejected or slop")
          end
        end
      end
    end
  end
end

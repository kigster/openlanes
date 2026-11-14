# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rename < Step
        # Where an ordinary Completed round takes its folder, once any verdict
        # is known: approved, built locally, held for a partner, or promoted,
        # and then the `next:` line honoured.
        class Advance < Step
          # @param desk [Desk]
          # @param approval [Approval]
          # @param promotion [Promotion]
          # @param holds [Holds]
          def initialize(desk, approval:, promotion:, holds:)
            super(desk)
            @approval = approval
            @promotion = promotion
            @holds = holds
          end

          # @param round [Completed]
          # @param verdict [Symbol, nil] see {Verdicts.of}
          # @return [OpenLanes::Engine::Runner::Attempt]
          def call(round, verdict)
            return @approval.call(round) if verdict == :approved

            attempt = round.base.with(status: "Completed")
            return built_locally(attempt, round.ordinal) if verdict == :verified

            partner_running = running.any? { plan_of(it) == round.ordinal }
            target = Verdicts.target(round.agent, verdict, partner_running)
            return built_locally(attempt, round.ordinal) if local_only_review?(target, round.subject)

            moved(round, attempt, target, partner_running)
          end

          private

          def moved(round, attempt, target, partner_running)
            if target && partner_running && target == round.agent.holds_at
              attempt = @holds.hold(round.ordinal, target, attempt)
            elsif target
              moved = @promotion.call(round, attempt, target)
              return moved.attempt if moved.final

              attempt = moved.attempt
            end
            handoff = Plans::Ledger.handoff_after(round.reading, round.entry)
            handoff ? honour(handoff, round.subject, attempt) : attempt
          end

          # A build finished in a run that opens no pull request: 🟢 needs one,
          # so the folder cannot move, and failing the attempt would only start
          # the builder again on work that is done. Only the missing pull
          # request is forgiven, and pull-requests.md with it: a build that
          # deleted another file 🟢 requires is still reported.
          def local_only_review?(target, subject)
            return false unless target == :ready_for_review && !runner.publishes? && !subject.machine.may?(target)

            (Plans::STATUS_BY_KEY.fetch(target).requires - %w[pull-requests.md]).all? { subject.file?(it) }
          end

          # The build stays at 🟡, finished for this run, saying why.
          def built_locally(attempt, ordinal)
            finished_plans << ordinal
            attempt.with(note: "#{attempt.note}; built locally, no pull request in this run, so it waits for one")
          end

          # A `next:` that names someone who handles the plan's new state is
          # honoured by preferring them; one that does not is reported, and the
          # state's own agents take it, because a wrong name must not stall a plan.
          def honour(handoff, subject, attempt)
            current = fresh_by(subject.feature.ordinal) || subject
            named = runner.agents.find(handoff.next)
            return prefer(current, named, attempt) if named&.handles?(current.status)

            attempt.with(note: "#{attempt.note}; next: names #{handoff.next}, who #{misnamed(named, current)}")
          end

          def prefer(current, named, attempt)
            preferred_agents[current.feature.ordinal.to_s] = named.name
            attempt
          end

          def misnamed(named, current) = named ? "does not handle #{current.status}" : "is not an agent"
        end
      end
    end
  end
end

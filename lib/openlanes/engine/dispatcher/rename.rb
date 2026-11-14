# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # Where a plan's folder goes once a round has signed for itself: on to
      # the state the agent advances to ({Advance}), held for a partner
      # ({Holds}), back for a rejection, or into ⭕ for a question ({Parking}).
      # The build is published before the folder is asked whether it may move
      # to 🟢 ({Promotion}), and a reviewer's ({Review}) or verifier's
      # ({Verify}) verdict is counted before anything moves at all.
      #
      # {Settle} decides that a round ended Completed or Blocked; what that
      # does to the folder is decided here, and nowhere else.
      class Rename < Step
        # What a builder is told when its finished work has no way to be tested.
        HOW_TO_TEST_MAIL = <<~MAIL.freeze
          The build is done, but the pull request was not opened: plan.md has no
          `#{Lifecycle::Completion::HOW_TO_TEST}` section, and a pull request nobody can test is not
          ready for review. Add one to plan.md: the commands to run and what a person
          should see, as a list, covering every part of the build and not only yours.
          Change nothing else, then sign Completed again.
        MAIL

        # @param desk [Desk]
        def initialize(desk)
          super
          @holds = Holds.new(desk)
          @parking = Parking.new(desk)
          @verify = Verify.new(desk)
          promotion = Promotion.new(desk, publication: Publication.new(desk))
          @advance = Advance.new(desk, approval: Approval.new(desk), promotion:, holds: @holds)
          @review = Review.new(desk, advance: @advance)
        end

        # @!method park(job, base, entry)
        #   @return [OpenLanes::Engine::Runner::Attempt] see {Parking#park}
        # @!method assessed(job, base, note)
        #   @return [OpenLanes::Engine::Runner::Attempt] see {Parking#assessed}
        def_delegators :@parking, :park, :assessed

        # @!method apply_hold(ordinal)
        #   @return [void] see {Holds#apply_hold}
        def_delegators :@holds, :apply_hold

        # `starts_as`: the folder moves the moment the agent is dispatched, where
        # the topology allows, so backend-coder's start is what makes a plan 🟡.
        #
        # @return [OpenLanes::Plans::Subject] fresh, under whichever name it now has
        def rename_on_start(subject, agent)
          target = agent.starts_as
          return subject unless target && subject.machine.may?(target)

          subject.machine.promote!(target)
          Plans::Tree.new(dir: runner.tree.dir).find(subject.feature.ordinal) || subject
        end

        # A Completed entry: publish if the move is to 🟢, then move the folder,
        # and honour the `next:` line.
        #
        # @return [OpenLanes::Engine::Runner::Attempt]
        def complete(job, base, entry, reading)
          subject = fresh(job.task) or return base.with(ok: false, note: "plan folder vanished")
          signed(job, subject)
          # Only a reviewer rules. A builder that signed `Completed (approved)`
          # once had its own work taken as approved: the plan was parked as
          # finished at 🟡, never reviewed and never published.
          return assessed(job, base, entry.note) if assessor?(job.task.agent)

          ruled(Completed.new(job:, base:, subject:, entry:, reading:))
        end

        private

        def signed(job, subject)
          task = job.task
          remember(plan_of(job), task.agent.name, job.state, "Completed", task.round)
          Lifecycle::Completion.copy(subject) if task.agent.ledger.include?("plan.md")
        end

        def ruled(round)
          phase = round.agent.phase.to_s
          return @review.call(round) if phase == REVIEW_PHASE
          return @verify.call(round) if phase == Verification::PHASE && runner.verification

          @advance.call(round, phase == Verification::PHASE ? Verdicts.of(round.entry) : nil)
        end
      end
    end
  end
end

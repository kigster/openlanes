# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Start < Step
        # A plan made ready for a round once it is held: a review round opened,
        # the plan no longer finished, its checkout prepared, and the job built.
        class Launch < Step
          # @param desk [Desk]
          # @param jobs [Jobs]
          # @param settle [Settle] ends a review round's replacements
          def initialize(desk, jobs:, settle:)
            super(desk)
            @jobs = jobs
            @settle = settle
          end

          # Once a round, by whichever reviewer opens it: the rest start at 👀.
          #
          # @param from [Symbol] the state the plan was dispatched in
          # @return [void]
          def open(agent, subject, from)
            mark(agent, subject, from) if agent.phase.to_s == REVIEW_PHASE && !runner.dry_run?
            finishes.unfinish(subject)
          end

          # @param from [Symbol] the state the plan was dispatched in, whose
          #   rounds this one is counted among
          # @return [OpenLanes::Engine::Dispatcher::Job]
          def job(agent, subject, from)
            ordinal = subject.feature.ordinal.to_s
            round = history[[ordinal, agent.name]].count { |h| h[:state] == from } + 1
            task = prepare(agent, subject, round)
            pending(@jobs.build(task,
              timed_handle(ordinal, agent, round, subject),
              from:,
              state: subject.status.key,
              rounds: rounds_allowed(agent, subject)))
          end

          private

          # The pull request marked as being read: by the reviewer that opens
          # the round, and again by each later group.
          def mark(agent, subject, from)
            if from == :ready_for_review
              runner.reviews.started(subject)
              @settle.end_replacements(subject.feature.ordinal.to_s)
            elsif agent.review_stage > 1
              # The first group's verdict took `review-in-progress` off; a
              # later group reading the pull request puts it back.
              runner.reviews.started(subject)
            end
          end

          # A rebase still to run shows what it will do.
          def pending(job)
            refresh = job.task.refresh
            job.message = refresh.summary if refresh&.kind == :pending
            job
          end

          # A checkout another agent is working in is never moved under it.
          def prepare(agent, subject, round)
            ordinal = subject.feature.ordinal.to_s
            runner.prepare(agent, subject, round, refresh: running.none? { plan_of(it) == ordinal }, hold: rebases.hold(ordinal))
          end

          # A round a person gave more time to (E1) starts with it.
          def timed_handle(ordinal, agent, round, subject)
            handle = @jobs.handle(ordinal, agent, round)
            bonus = runner.dry_run? ? 0 : extensions.take_seconds(subject.feature.path, agent.name, subject.status.key)
            handle.extend!(bonus) if bonus.positive?
            handle
          end
        end
      end
    end
  end
end

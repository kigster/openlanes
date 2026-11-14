# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Start < Step
        # Rebase a waiting pull request's branch onto `main` in its plan's
        # checkout (U3). Only the scheduling is the dispatcher's: a stop on
        # conflicts becomes a rebaser job, as a pre-run rebase's does (D10),
        # and what follows either way is the keeper's. A plan that cannot be
        # started now, with every slot taken or somebody in it, is asked about
        # on the next sweep.
        class Conflicts < Step
          # @param desk [Desk]
          # @param claims [Claims]
          # @param jobs [Jobs]
          # @param rebase [#call] starts a rebase job, `(job, ordinal)`
          def initialize(desk, claims:, jobs:, rebase:)
            super(desk)
            @claims = claims
            @jobs = jobs
            @rebase = rebase
          end

          # @param upkeep [OpenLanes::Engine::Upkeep::Keeper]
          # @param conflict [OpenLanes::Engine::Upkeep::Conflict]
          # @return [void]
          def call(upkeep, conflict)
            ordinal = conflict.ordinal
            resolver = runner.agents.find(Rebase::RESOLVER) or return no_resolver(conflict)
            subject = claimed(ordinal, resolver) or return upkeep.later(conflict)
            task = prepared(resolver, subject, ordinal)
            return conflict_job(task, conflict) if task.refresh&.conflicted?

            begin
              said(upkeep.rebased(conflict, task.checkout, task.refresh), ordinal)
            ensure
              locks.release(ordinal)
            end
          end

          private

          def no_resolver(conflict)
            UI.log("conflicts left on PR ##{conflict.number}: no #{Rebase::RESOLVER} is defined", level: :warn, plan: conflict.ordinal)
          end

          # @return [OpenLanes::Plans::Subject, nil] the plan, reserved and locked, or nil to ask later
          def claimed(ordinal, resolver)
            subject = runner.tree.find(ordinal)
            return nil if subject.nil? || running.size >= runner.jobs || untouchable.include?(ordinal) || !runner.claim(subject)
            return nil unless @claims.reserve(ordinal, subject, resolver)
            return subject if @claims.lock(ordinal, subject)

            locks.unreserve(ordinal)
            nil
          end

          def prepared(resolver, subject, ordinal)
            runner.prepare(resolver, subject, 1, hold: rebases.hold(ordinal))
          rescue StandardError
            locks.release(ordinal)
            raise
          end

          def conflict_job(task, conflict)
            state = task.subject.status.key
            @rebase.call(@jobs.build(task, Execution::Executor::Handle.new, from: state, state:, sweep: conflict), conflict.ordinal)
          end

          def said(report, ordinal) = UI.log(report.note, level: report.ok == false ? :warn : :info, plan: ordinal)
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    module Upkeep
      # What follows a conflicted pull request's rebase in its plan's
      # checkout (U3): push what moved, and have GitHub asked again, which
      # relabels it `conflicts-resolved` once it merges clean. The pushing
      # is a callable, so this knows no publisher and no runner.
      class Resolution
        # @param owed [Owed]
        # @param push [#call] pushes a checkout's HEAD, raising
        #   {OpenLanes::Error} when refused
        def initialize(owed:, push:)
          @owed = owed
          @push = push
        end

        # No conflict stopped the rebase: push at most once per head of
        # `main`. A rebase held by a spent ladder is not done, and is not
        # tried again until `main` moves (D10).
        #
        # @param conflict [Conflict]
        # @param checkout [Vcs::Worktree::Checkout, nil]
        # @param outcome [Vcs::Refresh::Outcome, nil]
        # @return [Report]
        def rebased(conflict, checkout, outcome)
          number = conflict.number
          unless checkout && outcome&.done?
            return Report.new(ok: false, note: "PR ##{number} not rebased: #{outcome&.reason || "no checkout to rebase in"}")
          end
          return Report.new(ok: true, note: "PR ##{number} already pushed against this main; waiting for it to move") unless @owed.pushable?(conflict)

          pushed(conflict, checkout, "PR ##{number} rebased onto main and pushed")
        end

        # rebaser's job ended. Resolved, it is pushed. Aborted,
        # `conflicts` stays, and the next sweep tries one step up the ladder
        # until it is spent (+held+); then the next move of `main` starts it
        # again (D10).
        #
        # @param conflict [Conflict]
        # @param checkout [Vcs::Worktree::Checkout]
        # @param result [Execution::Executor::Result, Exception]
        # @param held [Object, nil] {Rebase#hold}: set once the ladder is spent
        # @return [Report]
        def finished(conflict, checkout, result, held:)
          number = conflict.number
          return Report.new(ok: false, note: "conflicts on PR ##{number}: #{result.message}") if result.is_a?(Exception)

          unless result.ok
            @owed.recheck(conflict) unless held
            return Report.new(ok: nil, note: "conflicts on PR ##{number}: #{result.note}")
          end

          pushed(conflict, checkout, "PR ##{number} pushed after its rebase onto main; #{result.note}")
        end

        private

        # @return [Report]
        def pushed(conflict, checkout, note)
          @push.call(checkout)
          @owed.recheck(conflict)
          Report.new(ok: true, note:)
        rescue OpenLanes::Error => e
          Report.new(ok: false, note: "PR ##{conflict.number} rebased but not pushed: #{Upkeep.first_line(e)}")
        end
      end
    end
  end
end

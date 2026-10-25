# frozen_string_literal: true

module OpenLanes
  module Engine
    module Steps
      # One pass over every assessed 🏁 plan, at most once per {POLL}
      # seconds, moving each on by what its merges did. A note is logged
      # when it changes, not on every pass that finds it unchanged.
      class Merges
        # @param context [Context]
        def initialize(context)
          @context = context
          @interval = Interval.new(POLL)
          @said = {}
        end

        # @return [void]
        def call
          runner = @context.runner
          merging = runner.merging or return
          return if runner.dry_run? || !@interval.due?

          busy = @context.busy.call
          runner.in_scope.each { advance(merging, it, busy) }
          # Read again: a merge above may have queued checkouts, and an agent
          # started since the first read must keep its HEAD (R5).
          merging.rebase_queued(busy: @context.busy.call).each { UI.log(it) }
        end

        private

        # @return [void]
        def advance(merging, subject, busy)
          ordinal = subject.feature.ordinal.to_s
          return if busy.include?(ordinal) || !merging.assessed?(subject)

          report(ordinal, merging.advance(subject))
        rescue OpenLanes::Error => e
          UI.log("merge not settled: #{Steps.first_line(e)}", level: :warn, plan: ordinal)
        end

        # @return [void]
        def report(ordinal, result)
          return if @said[ordinal] == result.note && !result.to

          @said[ordinal] = result.note
          @context.reopen.call(ordinal) if result.to
          UI.log(result.note, plan: ordinal)
          @context.wake.call if result.to || result.merged
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    module Unblocking
      # A drained plan's agents get their rounds back: a block is a question,
      # not the agent running out of turns. A failed drain is remembered with
      # its reason, which the idle line names until `blocked.md` changes.
      class Settler
        # @param context [Steps::Context]
        # @param history [#call] see {Unblocking.drainer}
        # @param reopener [Reopener]
        def initialize(context, history:, reopener:)
          @context = context
          @history = history
          @reopener = reopener
          @failed = {}
        end

        # @return [Hash{String => String}] each failed plan's reason
        def failures = @failed

        # A new answer set is about to be tried; the old failure no longer says anything.
        #
        # @param ordinal [String]
        # @return [void]
        def forget(ordinal) = @failed.delete(ordinal)

        # @param drain [Drain]
        # @return [void]
        def call(drain)
          outcome = drain.outcome
          return failed(drain, outcome) if outcome.is_a?(Exception) || !outcome.ok

          @failed.delete(drain.ordinal)
          @reopener.call(drain, outcome) unless outcome.waiting.empty?
          drained(drain.ordinal)
          UI.log(outcome.cleared? ? "unblocked: blocked.md retired" : "unblock folded #{outcome.folded.size}",
            plan: drain.ordinal)
        end

        private

        # @return [void]
        def drained(ordinal)
          @history.call(ordinal)
          @context.reopen.call(ordinal)
          @context.wake.call
        end

        # @return [void]
        def failed(drain, outcome)
          note = outcome.is_a?(Exception) ? outcome.message : outcome.note
          @failed[drain.ordinal] = note
          UI.log("unblock failed: #{note}", level: :warn, plan: drain.ordinal)
        end
      end
    end
  end
end

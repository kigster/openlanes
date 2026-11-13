# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # One running invocation. `from` is the state the plan showed when the
      # agent was picked; `state` is the one it ran under, after any
      # `starts_as` rename. History is keyed by `state`: backend-coder picked at ⭐
      # works at 🟡, and keying by ⭐ would offer him 🟡 afterwards as though
      # he had never been there (the 020.00 regression, run twice over).
      Job = Struct.new(:key,
        :task,
        :thread,
        :handle,
        :started_at,
        :file,
        :status,
        :message,
        :up,
        :down,
        :subagents,
        :result,
        :from,
        :state,
        :frame,
        :history,
        :context,
        :running,
        :rebase,
        :recorded_session,
        :journal,
        :journaled,
        :journal_round,
        :sweep,
        :rounds) do
        # @return [Boolean]
        def finished? = !thread.alive?
      end
    end
  end
end

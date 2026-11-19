# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # A person's request to compact one running agent's session (W28),
      # and, once the harness has acted on it, how that went.
      # {Live::Commands} holds on to it and replies once {#finished?}.
      #
      # @!attribute [r] model
      #   @return [String, nil] the model the session carries on in; nil keeps
      #     the one it was started on
      # @!attribute [r] status
      #   @return [String, nil] "done" once the continuation has started,
      #     "refused" when it could not be, nil while under way
      # @!attribute [r] reason
      #   @return [String, nil]
      # @!attribute [r] restart
      #   @return [Boolean] whether the agent, stopped for a compaction that
      #     could not happen, gets its round back to start again afresh
      Compaction = Struct.new(:model, :status, :reason, :restart) do
        # @return [Boolean]
        def finished? = !status.nil?

        # @param reason [String]
        # @return [void]
        def done!(reason) = settle("done", reason)

        # @param reason [String]
        # @param restart [Boolean] the agent stopped for nothing, and is
        #   started again from its resume note in a fresh session
        # @return [void]
        def refuse!(reason, restart: false)
          self.restart = restart
          settle("refused", restart ? "#{reason}; it restarts from its resume note in a fresh session" : reason)
        end

        private

        # The reason is set before the status, so a reader on another thread
        # that sees it finished also sees why.
        #
        # @return [void]
        def settle(status, reason)
          self.reason = reason
          self.status = status
        end
      end
    end
  end
end

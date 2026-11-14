# frozen_string_literal: true

module OpenLanes
  module Engine
    # Decides whether a finished builder's work is run through
    # {PreReviewGate}, and runs it.
    #
    # It runs on the builder's job thread, after the agent exits and before
    # the tick settles the job: a suite takes minutes, and run from settle it
    # would stop every other plan's tick for as long. Settle only reads the
    # verdict the job carries.
    class ReviewGating
      # @param config [#call] returns the project's {OpenLanes::Config}, read
      #   when the gate is asked, so a test or a reload sees the current one
      # @param gate [#call] {PreReviewGate} unless a spec stands in
      def initialize(config: -> { Config.current }, gate: PreReviewGate)
        @config = config
        @gate = gate
      end

      # @param task [OpenLanes::Engine::Runner::Task]
      # @param result [Object] what the executor returned
      # @param entry [OpenLanes::Plans::Ledger::Entry, nil] the agent's last
      #   ledger line
      # @return [PreReviewGate::Verdict, nil] nil when the gate does not apply
      def call(task, result, entry)
        return nil unless applies?(task, result, entry)

        timeout = @config.call.review_gate_timeout
        @gate.call(task.root, **{ timeout: }.compact)
      end

      private

      # Only a builder that ended cleanly and signed Completed this round is
      # on its way to review; a Blocked or failed round runs no suite.
      #
      # @return [Boolean]
      def applies?(task, result, entry)
        return false unless @config.call.review_gate
        return false unless task.agent.builder?
        return false unless result.respond_to?(:ok) && result.ok

        entry&.completed? == true && entry.round == task.round
      end
    end
  end
end

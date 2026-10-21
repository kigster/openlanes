# frozen_string_literal: true

module OpenLanes
  module Adapters
    # What one CLI can do, declared in one place. Every adapter states every
    # field: a capability inherited as a silent default is how codex was once
    # assumed to refuse denied tools it never refused.
    #
    # @!attribute [r] compacts
    #   @return [Boolean] an agent on this CLI can be compacted and carried on
    #     in the same session
    # @!attribute [r] resumes
    #   @return [Boolean] {Base#argv} honours {Invocation#resume}
    # @!attribute [r] enforces_tool_denial
    #   @return [Boolean] the CLI itself refuses the denied tools
    # @!attribute [r] compact_prompt
    #   @return [String, nil] what, sent into a resumed session, compacts it;
    #     nil exactly when {#compacts} is false
    Capabilities = Data.define(:compacts, :resumes, :enforces_tool_denial, :compact_prompt) do
      def initialize(compacts:, resumes:, enforces_tool_denial:, compact_prompt:)
        if compacts == compact_prompt.nil?
          raise ArgumentError, "compact_prompt must be given exactly when compacts is true"
        end

        super
      end
    end
  end
end

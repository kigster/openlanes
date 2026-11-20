# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What the caller of {Executor#call} or {Executor#invocation} asked for
      # beyond the agent and the plan, with the defaults both take.
      #
      # @!attribute [r] root
      #   @return [String] the checkout the agent works in
      # @!attribute [r] control
      #   @return [String, nil] the control file the prompt names
      # @!attribute [r] round
      #   @return [Integer] which attempt on this plan this is
      # @!attribute [r] successor
      #   @return [String, nil] who the agent names on its `next:` line
      # @!attribute [r] partners
      #   @return [Array<OpenLanes::Agents::Agent>] the others on this plan now
      # @!attribute [r] rebase
      #   @return [OpenLanes::Vcs::Refresh::Outcome, nil] a stopped rebase to resolve
      # @!attribute [r] resume
      #   @return [String, nil] the previous round's session id (M1), carried on
      #   with this round's prompt; ignored by a CLI that cannot resume, and
      #   dropped for a fresh start when the CLI cannot find it
      # @!attribute [r] brief
      #   @return [String] a section the caller adds for this invocation alone,
      #   such as the slugs a curator may reuse ({Memory.known})
      Request = Data.define(:root, :control, :round, :successor, :partners, :rebase, :resume, :brief) do
        def initialize(root:, control: nil, round: 1, successor: nil, partners: [], rebase: nil, resume: nil, brief: "") = super
      end
    end
  end
end

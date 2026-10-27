# frozen_string_literal: true

module OpenLanes
  module Execution
    class AgentProcess
      # Which agent, on which plan: what names its files and its title.
      # +control+ is the file named in the agent's prompt, which its agent
      # supervisor tells `INTERRUPT` on USR1 (C2 in plan 041); nil when the
      # caller has none.
      Label = Data.define(:plan, :agent, :control) do
        # @param plan [String]
        # @param agent [String]
        # @param control [String, nil]
        def initialize(plan:, agent:, control: nil) = super

        # @return [String] `005.00-backend-coder`
        def to_s = "#{plan}-#{agent}"
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Execution
    class AgentProcess
      # Which agent, on which plan: what names its files and its title.
      Label = Data.define(:plan, :agent) do
        # @return [String] `005.00-backend-coder`
        def to_s = "#{plan}-#{agent}"
      end
    end
  end
end

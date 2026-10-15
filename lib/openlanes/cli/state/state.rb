# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes state` — a plan's `state.json`, read and signed. Agents sign
    # through this rather than editing the file, because the command takes the
    # lock that keeps two agents on one plan from overwriting each other.
    module State
      # Both subcommands name a plan and need its folder.
      module Locating
        private

        # @param options [Hash]
        # @return [OpenLanes::Plans::PlanState]
        def plan_state_for(options)
          tree = tree_for(options).everything
          ordinal = Plans::Ordinal.parse(options[:plan].to_s)
          subject = ordinal && tree.find(ordinal)
          refuse("No plan #{options[:plan]} in #{tree.dir}.\n\nKnown: #{tree.ordinals.join(", ")}", 66) unless subject

          Plans::PlanState.for(subject.feature.path)
        end
      end
    end
  end
end

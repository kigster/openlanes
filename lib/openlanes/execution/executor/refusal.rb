# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The answers {Executor#call} gives without starting anything.
      module Refusal
        # What an invocation that never started spent.
        NOTHING = { up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0 }.freeze

        module_function

        # @param agent [OpenLanes::Agents::Agent]
        # @return [OpenLanes::Execution::Executor::Result]
        def dry_run(agent) = Result.new(ok: true, note: "dry run - would invoke #{agent.name}", **NOTHING)

        # A confined agent on a CLI that cannot enforce its confinement is not
        # started at all: a prompt that says "only spec.md" is a request.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @param profile [OpenLanes::Agents::Profile]
        # @return [OpenLanes::Execution::Executor::Result, nil] nil when it may start
        def unconfinable(agent, profile)
          return nil unless agent.confined? && !profile.adapter.confines?

          Result.new(ok: false,
**NOTHING,
            note: "#{agent.name} is confined to #{agent.confined_to.join(", ")}, and #{profile.adapter.executable} cannot enforce that")
        end
      end
    end
  end
end

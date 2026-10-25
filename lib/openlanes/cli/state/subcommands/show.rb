# frozen_string_literal: true

require "json"

module OpenLanes
  module CLI
    module State
      # `openlanes state show` — the plan's `state.json`, on STDOUT, so it
      # pipes into `jq`.
      class Show < Base
        include Locating

        desc "Print a plan's state.json"

        option :plan, required: true, desc: "Which plan: NNN or NNN.MM"

        example [
          "--plan 003",
          "--plan 003 | jq '.stages[] | {agent, round, status, model, seconds}'",
          "--plan 015 | jq '.rulings[]? | {at, kind, outcome, reason}'"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          $stdout.puts(JSON.pretty_generate(plan_state_for(options).read))
        end
      end
    end
  end
end

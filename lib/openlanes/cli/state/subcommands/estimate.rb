# frozen_string_literal: true

module OpenLanes
  module CLI
    module State
      # `openlanes state estimate` — a running agent's answer to the
      # harness asking how much more time it needs (E2).
      #
      # A `state` subcommand, and not a mail to the harness, because
      # `openlanes state` is the one command every agent is already granted,
      # the confined ones included: the answer needs no new tool grant, and
      # it lands on the request that asked, where the engine reads it on its
      # next tick.
      class Estimate < Base
        include Locating

        desc "Say how much more time a running agent needs, when its control file asks ESTIMATE"

        option :plan, required: true, desc: "Which plan: NNN or NNN.MM"
        option :agent, required: true, desc: "The agent answering"
        option :minutes, required: true, desc: "How many more minutes: 20, or 90s, 20m, 1.5h"
        option :why, desc: "What the time is for, in a line"

        example [
          %(--plan 003 --agent #{OpenLanes::Agents::Names::BACKEND_CODER} --minutes 20 --why "two units left: B3 and its specs")
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          seconds = Plans::Estimate.seconds(options[:minutes]) ||
                    refuse("--minutes #{options[:minutes]} is not a time above zero: say 20, or 90s, 20m, 1.5h", 64)
          state = plan_state_for(options)
          state.estimate_extension!(agent: options[:agent], seconds:, why: options[:why]) ||
            refuse("Nobody is waiting on an estimate from #{options[:agent]} on #{options[:plan]}; carry on.", 64)
          return if quiet?(options)

          UI.line("#{options[:agent]}: #{(seconds / 60.0).round} more minutes asked for, " \
                  "in #{File.basename(state.dir)}/#{Plans::PlanState::FILENAME}")
        end
      end
    end
  end
end

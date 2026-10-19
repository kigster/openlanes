# frozen_string_literal: true

module OpenLanes
  module CLI
    module State
      # `openlanes state sign` — an agent's ledger line, written into the
      # plan's `state.json`.
      class Sign < Base
        include Locating

        desc "Sign a plan's ledger: Started, Completed, Almost completed, Interrupted or Blocked"

        option :plan, required: true, desc: "Which plan: NNN or NNN.MM"
        option :agent, required: true, desc: "The agent signing"
        option :round, required: true, desc: "Which round this is, as the prompt states it"
        option :status, required: true, values: Plans::Ledger::STATUSES, desc: "Where the agent stands"
        option :note, desc: "A word or two the harness reads, e.g. approved, rejected, technical, product"
        option :next, desc: "Only with Completed: the agent that should go next"

        example [
          "--plan 003 --agent luke-backend --round 1 --status Started",
          "--plan 003 --agent hansolo-reviewer --round 1 --status Completed --note approved",
          "--plan 003 --agent yoda-writer --round 1 --status Completed --next luthen-rael-planner"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          state = plan_state_for(options)
          signature = begin
            state.sign!(agent: options[:agent],
              round:      Integer(options[:round].to_s, exception: false) || refuse("--round must be a number", 64),
              status:     options[:status],
              note:       options[:note],
              next_agent: options[:next])
          rescue OpenLanes::Error => e
            refuse(e.message, 64)
          end

          return if quiet?(options)

          UI.line("#{signature["agent"]}: #{signature["status"]}, round #{signature["round"]} " \
                  "in #{File.basename(state.dir)}/#{Plans::PlanState::FILENAME}")
        end
      end
    end
  end
end

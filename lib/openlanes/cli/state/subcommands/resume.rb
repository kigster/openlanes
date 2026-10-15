# frozen_string_literal: true

module OpenLanes
  module CLI
    module State
      # `openlanes state resume` — what an interrupted agent leaves for
      # whoever runs next, most likely itself.
      #
      # It used to be a `RESUME: ...` mail, which the next round had to read
      # and believe. This is a record with fixed fields, kept in `state.json`
      # under `last-known-state`, one per agent.
      class Resume < Base
        include Locating

        desc "Record where an interrupted agent stood, for the next round to resume from"

        option :plan, required: true, desc: "Which plan: NNN or NNN.MM"
        option :agent, required: true, desc: "The agent recording"
        option :round, required: true, desc: "Which round this is, as the prompt states it"
        option :status, default: "Interrupted", values: Plans::Ledger::STATUSES, desc: "Where the agent stands"
        option :done, desc: "What is finished, comma-separated"
        option :remaining, desc: "What is not, comma-separated"
        option :next_step, desc: "The exact first thing to do on resuming"
        option :files, desc: "Files touched, comma-separated"

        example [
          %(--plan 003 --agent luke-backend --round 1 --done "B1,B2" --remaining "B3" --next-step "run rspec spec/openlanes/live" --files lib/openlanes/live/mail.rb)
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          state = plan_state_for(options)
          entry = begin
            state.record_last_known(options[:agent],
              Plans::LastKnownState.new(source: "agent",
                round:         Integer(options[:round].to_s, exception: false) || refuse("--round must be a number", 64),
                status:        options[:status],
                done:          list(options[:done]),
                remaining:     list(options[:remaining]),
                next_step:     options[:next_step],
                files_touched: list(options[:files])))
          rescue OpenLanes::Error => e
            refuse(e.message, 64)
          end

          return if quiet?(options)

          UI.line("#{options[:agent]}: #{entry.status}, round #{entry.round}, resume record " \
                  "in #{File.basename(state.dir)}/#{Plans::PlanState::FILENAME}")
        end

        private

        # @param text [String, nil]
        # @return [Array<String>]
        def list(text) = text.to_s.split(",").map(&:strip).reject(&:empty?)
      end
    end
  end
end

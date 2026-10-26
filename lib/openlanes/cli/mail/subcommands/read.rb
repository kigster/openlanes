# frozen_string_literal: true

module OpenLanes
  module CLI
    module Mail
      # `openlanes mail read` — what is waiting for one agent.
      #
      # Nothing waiting is the ordinary result of a poll, so it is not an
      # error and not even STDOUT: the messages are the deliverable, and an
      # empty one is empty.
      class Read < Base
        include Locating

        desc "Print the messages waiting for an agent in a plan's mailbox"

        option :plan, required: true, desc: "Which plan: NNN or NNN.MM"
        option :for, required: true, desc: "The agent reading"
        option :after, default: "0", desc: "Only messages numbered above this, so a poll shows what is new"

        example [
          "--plan 003 --for #{OpenLanes::Agents::Names::FRONTEND_CODER}            # everything addressed to #{OpenLanes::Agents::Names::FRONTEND_CODER}",
          "--plan 003 --for #{OpenLanes::Agents::Names::FRONTEND_CODER} --after 4  # only what arrived since #4"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          quiet?(options)
          mailbox = mailbox_for(options)
          after = options[:after].to_i
          waiting = mailbox.for(options[:for], after:)

          if waiting.empty?
            UI.line("Nothing for #{options[:for]}#{" after ##{after}" if after.positive?}") unless quiet?(options)
            return
          end

          puts waiting.join("\n")
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module CLI
    module Mail
      # `openlanes mail ack` — say a message was read.
      #
      # Delivery cannot say it: a message that reached `state.json` may sit
      # there for a whole round while its reader never polls. Only the reader
      # knows, so only the reader writes `read: "yes"`.
      class Ack < Base
        include Locating

        desc "Mark a message in a plan's mailbox as read"

        argument :number, type: :string, required: true, desc: "The message's number, as `mail read` prints it"

        option :plan, required: true, desc: "Which plan: NNN or NNN.MM"
        option :for, required: true, desc: "The agent that read it, who must be its recipient"

        example [
          "--plan 003 --for rey-frontend 4   # rey read #4"
        ]

        # @param number [String]
        # @param options [Hash]
        # @return [void]
        def call(number:, **options)
          quiet?(options)
          mailbox = mailbox_for(options)
          message = begin
            mailbox.ack(number, by: options[:for])
          rescue OpenLanes::Error => e
            refuse(e.message, 65)
          end

          return if quiet?(options)

          UI.line("##{message.number} read by #{message.to}, in #{File.basename(mailbox.dir)}/#{Plans::PlanState::FILENAME}")
        end
      end
    end
  end
end

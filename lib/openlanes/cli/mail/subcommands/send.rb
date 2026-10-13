# frozen_string_literal: true

module OpenLanes
  module CLI
    module Mail
      # `openlanes mail send` — leave a message for the other half.
      class Send < Base
        include Locating

        desc "Append a message to a plan's mailbox"

        argument :body, type: :string, required: true, desc: "The message, quoted"

        option :plan, required: true, desc: "Which plan: NNN or NNN.MM"
        option :from, required: true, desc: "The agent writing"
        option :to, required: true, desc: "The agent it is for"

        example [
          %(--plan 003 --from luke-backend --to rey-frontend "GET /returns/:id is up; errors come back as {error: {code, message}}")
        ]

        # @param body [String]
        # @param options [Hash]
        # @return [void]
        def call(body:, **options)
          quiet?(options)
          mailbox = mailbox_for(options)
          message = begin
            mailbox.append(from: options[:from], to: options[:to], body:)
          rescue OpenLanes::Error => e
            refuse(e.message, 64)
          end

          return if quiet?(options)

          # One line, not a box: an agent runs this between steps, and a
          # four-line frame around "#7 → rey-frontend" is noise it reads.
          UI.line("##{message.number} → #{message.to}, in #{File.basename(mailbox.dir)}/#{Plans::PlanState::FILENAME}")
        end
      end
    end
  end
end

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
          %(--plan 003 --from #{OpenLanes::Agents::Names::BACKEND_CODER} --to #{OpenLanes::Agents::Names::FRONTEND_CODER} "GET /returns/:id is up; errors come back as {error: {code, message}}")
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
          publish(mailbox, message)

          return if quiet?(options)

          # One line, not a box: an agent runs this between steps, and a
          # four-line frame around "#7 → frontend-coder" is noise it reads.
          UI.line("##{message.number} → #{message.to}, in #{File.basename(mailbox.dir)}/#{Plans::PlanState::FILENAME}")
        end

        private

        # Hand the message to the harness over Redis, when there is one.
        # `state.json` already has it, so no Redis is not a failure and says
        # nothing: an agent that sees a warning on every send learns to
        # ignore warnings. The keys are the plans directory's checkout, not
        # this process's, because an agent in a worktree sends to the run in
        # the main checkout.
        #
        # @param mailbox [OpenLanes::Plans::Mailbox]
        # @param message [OpenLanes::Plans::Mailbox::Message]
        # @return [void]
        def publish(mailbox, message)
          feature = Plans::Feature.parse(mailbox.dir) or return
          root = File.dirname(mailbox.dir, 2)
          store = Live.connect(Live.redis_url(config: Config.current))
          begin
            Live::Mail.new(store:, keys: Live.keys(root:)).publish(plan: feature.ordinal, message:)
          ensure
            store.close
          end
        rescue Live::Unavailable
          nil
        end
      end
    end
  end
end

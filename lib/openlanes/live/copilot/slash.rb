# frozen_string_literal: true

module OpenLanes
  module Live
    class Copilot
      # The three things a person may tell the run from the copilot's box
      # (plan 020.00): `/stop NNN`, `/restart NNN` and `/concurrency N`. Each
      # becomes an engine {Command} on the same stream the page's buttons use
      # (W13), so c3po-operator stays read-only and the commands get the
      # gate's idempotency, replies and logging for nothing.
      #
      # The grammar lives here and nowhere else: the page draws a hint but
      # parses nothing, so page and server cannot disagree on what a command is.
      module Slash
        # What a slash message that is not one of the three is answered with.
        #
        # @!attribute [r] text
        #   @return [String] the usage, then why this message was not a command
        Help = Data.define(:text)

        # The usage, which the help turn starts with.
        USAGE = <<~TEXT.chomp
          Slash commands:
          /stop NNN — stop every agent on plan NNN and take it off the board
          /restart NNN — start plan NNN again when it is on the board with no agent
          /concurrency N — let N agents run at once; lowering it waits for agents to finish
        TEXT

        # Word to the command kind it queues.
        PLAN_KINDS = { "stop" => "stop_plan", "restart" => "restart_plan" }.freeze

        # @param text [String] the person's message, stripped
        # @param id [String] the message id, which becomes the command's, so
        #   the engine's reply and its copilot turn name the message
        # @return [OpenLanes::Live::Command, Help, nil] nil when +text+ is not
        #   a slash message, so it goes to the copilot as before
        def self.parse(text, id:)
          return unless text.start_with?("/")

          word, *args = text.delete_prefix("/").split
          word = word.to_s.downcase
          if PLAN_KINDS.key?(word)
            plan_command(word, args, id)
          elsif word == "concurrency"
            concurrency(args, id)
          else
            help("/#{word} is not one of them.")
          end
        end

        # @return [OpenLanes::Live::Command, Help]
        def self.plan_command(word, args, id)
          plan = Plans::Ordinal.parse(args.first) if args.size == 1
          return help("/#{word} needs a plan number, like /#{word} 20 or /#{word} 020.00.") unless plan

          command(id, PLAN_KINDS.fetch(word), plan: plan.to_s)
        end

        # @return [OpenLanes::Live::Command, Help]
        def self.concurrency(args, id)
          limit = args.first.to_i if args.size == 1 && args.first.match?(/\A\d+\z/)
          return help("/concurrency needs a whole number of at least 1, like /concurrency 3.") unless limit&.positive?

          command(id, "set_concurrency", limit:)
        end

        # @return [OpenLanes::Live::Command]
        def self.command(id, kind, plan: nil, **payload)
          Command.parse("id" => id,
            "kind" => kind,
            "plan" => plan,
            "payload" => payload.transform_keys(&:to_s).merge("source" => "copilot"))
        end

        # @return [Help]
        def self.help(why) = Help.new(text: "#{USAGE}\n\n#{why}")

        private_class_method :plan_command, :concurrency, :command, :help
      end
    end
  end
end

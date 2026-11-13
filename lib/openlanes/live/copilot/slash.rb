# frozen_string_literal: true

module OpenLanes
  module Live
    class Copilot
      # What a person may tell the run from the copilot's box (plans 020.00
      # and 069.00), listed in {COMMANDS}. Each becomes an engine {Command} on
      # the same stream the page's buttons use (W13), so the commands get the
      # gate's idempotency, replies and logging for nothing. The copilot agent
      # proposes; only the person, by typing one of these, commands.
      #
      # The grammar lives here and nowhere else: the page draws a hint but
      # parses nothing, so page and server cannot disagree on what a command is.
      module Slash
        # What a slash message that is not a command is answered with.
        #
        # @!attribute [r] text
        #   @return [String] the usage, then why this message was not a command
        Help = Data.define(:text)

        # A read-only question the copilot answers itself, from the engine's
        # snapshot in Redis; it never reaches the engine (plan 069.00, D4).
        #
        # @!attribute [r] kind
        #   @return [String] status or stats
        # @!attribute [r] plan
        #   @return [String, nil] the ordinal `/status NNN` names
        Query = Data.define(:kind, :plan)

        # One slash command: its word, how it is typed, and what it does.
        # README.md's "Copilot commands" section lists the same rows, and a
        # spec holds the two together.
        Entry = Data.define(:name, :syntax, :summary)

        # Every slash command, the one table the usage and README read.
        COMMANDS = [
          Entry.new(name: "stop", syntax: "/stop NNN", summary: "stop every agent on plan NNN and take it off the board"),
          Entry.new(name: "restart",
            syntax:  "/restart NNN",
            summary: "start plan NNN again when it is on the board with no agent"),
          Entry.new(name: "concurrency",
            syntax:  "/concurrency N",
            summary: "let N agents run at once; lowering it waits for agents to finish"),
          Entry.new(name: "restart-web",
            syntax:  "/restart-web",
            summary: "stop the control room, rebuild its page and start it again; needs `openlanes start`"),
          Entry.new(name: "status",
            syntax:  "/status [NNN]",
            summary: "show every plan on the board, or plan NNN's agents and what each is doing; changes nothing"),
          Entry.new(name: "stats", syntax: "/stats", summary: "show the run's tokens, cost and agents so far; changes nothing")
        ].freeze

        # The usage, which the help turn starts with.
        USAGE = (["Slash commands:"] + COMMANDS.map { "#{it.syntax} — #{it.summary}" }).join("\n").freeze

        # Words answered without the engine.
        QUERIES = %w[status stats].freeze

        # Word to the command kind it queues.
        PLAN_KINDS = { "stop" => "stop_plan", "restart" => "restart_plan" }.freeze

        # @param text [String] the person's message, stripped
        # @param id [String] the message id, which becomes the command's, so
        #   the engine's reply and its copilot turn name the message
        # @return [OpenLanes::Live::Command, Query, Help, nil] nil when +text+ is not
        #   a slash message, so it goes to the copilot as before
        def self.parse(text, id:)
          return unless text.start_with?("/")

          word, *args = text.delete_prefix("/").split
          word = word.to_s.downcase
          return plan_command(word, args, id) if PLAN_KINDS.key?(word)
          return query(word, args) if QUERIES.include?(word)
          return concurrency(args, id) if word == "concurrency"
          return restart_web(args, id) if word == "restart-web"

          help("/#{word} is not one of them.")
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

        # @return [OpenLanes::Live::Command, Help]
        def self.restart_web(args, id)
          return help("/restart-web takes no arguments.") unless args.empty?

          command(id, "restart_web")
        end

        # @return [Query, Help]
        def self.query(word, args)
          return (args.empty? ? Query.new(kind: word, plan: nil) : help("/stats takes no arguments.")) if word == "stats"
          return Query.new(kind: word, plan: nil) if args.empty?

          plan = Plans::Ordinal.parse(args.first) if args.size == 1
          plan ? Query.new(kind: word, plan: plan.to_s) : help("/status takes at most a plan number, like /status 20.")
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

        private_class_method :plan_command, :concurrency, :restart_web, :query, :command, :help
      end
    end
  end
end

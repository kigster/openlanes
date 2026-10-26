# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes engine` — the factory's engine as a long-lived service, with
    # or without any plans. `openlanes start` runs it under a supervisor
    # with `--no-web` and serves the page beside it (S1); `just start` runs
    # it under mprocs the same way. Hidden: nobody types it but those two.
    #
    # It keeps the board published and the commands read, rescans the tree,
    # and starts agents as soon as an answer, a new plan or a hand edit makes
    # something dispatchable. It never ends on its own, not even once every
    # plan is finished: the page creates the next plan. It ends on Stop All
    # Local in the page, Ctrl-C or SIGTERM.
    #
    # The page is the only way in: every decision a person makes goes through
    # it, and the terminal is output only. So there is no headless fallback
    # (Redis and the control room are required, not hoped for), no dry run,
    # and no `--until`. `--no-web` does not make it headless: the page is
    # served by an `openlanes web` beside it, and the engine stays for it.
    #
    # Named for what it is rather than `Engine`, which inside `CLI` would
    # hide {OpenLanes::Engine} from every command here.
    class EngineCommand < Run
      desc "The factory's engine over the whole tree, until Stop All Local; `openlanes start` runs it"

      # Reads the `commands.start` section of `.openlanes.yml`: the one a
      # person writes for the factory, whichever process ends up reading it.
      #
      # @return [String]
      def self.command_name = "start"

      # Inherited from `run`, and meaningless here: the factory takes the
      # whole tree, a dry run publishes no board, and a factory that stops
      # its plans part way is a run.
      @arguments = []
      @options = options.reject { %i[dry_run until].include?(it.name) }

      option :plan,
        aliases: ["--plans"],
        desc:    "Only these plans, comma separated: NNN or NNN.MM, e.g. --plan 003,005.01. Default: the whole tree"
      option :web,
        type:    :boolean,
        default: true,
        desc:    "Serve the control room from this process; --no-web leaves it to an `openlanes web` " \
                 "run apart, as `just start` does, and the engine waits for that page"
      option :open,
        type:    :boolean,
        default: true,
        desc:    "Open the control room in the browser; --no-open only prints its URL"
      option :port,
        default: OpenLanes::Web::DEFAULT_PORT.to_s,
        desc:    "Port the control room listens on"
      listen_options

      option :rescan,
        default: Engine::Dispatcher::RESCAN_SECONDS.to_s,
        desc:    "Seconds between rescans of .plans while idle; a command from the page rescans at once"

      example [
        "                       # engine and control room, until Stop All Local or Ctrl-C",
        "--no-open              # print the control room's URL, open no browser",
        "--port 4848 -j 4       # somewhere other than 11000, four agents at a time",
        "--plan 005             # only plan 005, until stopped",
        "--no-web               # the engine alone, for a page `openlanes web` serves apart",
        "-I --admin-credentials admin:s3cret # the control room on every interface, behind a login"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        @rescan = rescan_for(options)
        super
      end

      private

      # @param options [Hash]
      # @return [Integer]
      def rescan_for(options)
        rescan = Integer(options.fetch(:rescan, Engine::Dispatcher::RESCAN_SECONDS), exception: false)
        refuse("--rescan takes a whole number of seconds, at least 1.", 64) unless rescan&.positive?
        rescan
      end

      # @return [String]
      def role = Supervision::ENGINE

      # @param _options [Hash]
      # @return [Array<String>] none: the engine takes the whole tree, or its --plan
      def registered_plans(_options) = []

      # The title says how busy the engine is (S5), refreshed each tick.
      #
      # @param registration [OpenLanes::Supervision::Registration]
      # @return [Proc]
      def on_board(registration) = ->(board) { registration.title("#{board.running} of #{board.jobs} agents busy") }

      # `--plan` is already the name the workflow reads; the listen
      # addresses and the login are the control room's.
      #
      # @param options [Hash]
      # @return [Hash]
      def prepare(options)
        listen = listen_for(options)
        options.merge(listen:, credentials: credentials_for(options, listen))
      end

      # @param tree [OpenLanes::Plans::Tree]
      # @param options [Hash]
      # @return [OpenLanes::Engine::StartWorkflow]
      def workflow(tree, options) = Engine.start(tree:, origin:, **options.except(:rescan), rescan: @rescan)
    end
  end
end

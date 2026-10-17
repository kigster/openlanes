# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes start` — the factory as a long-lived service: the engine and
    # the control room together, with or without any plans.
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
    # no `--no-web` and no `--until-settled`.
    class Start < Run
      desc "web + run in one: the engine and its control room, with or without plans, until Stop All Local"

      # Inherited from `run`, and meaningless here: a dry run publishes no
      # board, and a run without its page cannot be answered.
      @options = options.reject { %i[dry_run web stay until_settled].include?(it.name) }

      option :rescan,
        default: Engine::Dispatcher::RESCAN.to_s,
        desc:    "Seconds between rescans of .plans while idle; a command from the page rescans at once"

      example [
        "                       # engine and control room, until Stop All Local or Ctrl-C",
        "--no-open              # print the control room's URL, open no browser",
        "--port 4848 -j 4       # somewhere other than 11000, four agents at a time",
        "--plan 005             # only plan 005, until stopped"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        @rescan = Integer(options.fetch(:rescan, Engine::Dispatcher::RESCAN), exception: false)
        refuse("--rescan takes a whole number of seconds, at least 1.", 64) unless @rescan&.positive?

        super
      end

      private

      # @param tree [OpenLanes::Plans::Tree]
      # @param options [Hash]
      # @return [OpenLanes::Engine::StartWorkflow]
      def workflow(tree, options) = Engine.start(tree:, origin:, **options.except(:rescan), rescan: @rescan)
    end
  end
end

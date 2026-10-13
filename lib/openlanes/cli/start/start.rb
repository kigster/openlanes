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
      @options = options.reject { %i[dry_run web until_settled].include?(it.name) }

      option :rescan,
        default: Engine::Dispatcher::RESCAN.to_s,
        desc:    "Seconds between rescans of .plans while idle; a command from the page rescans at once"

      example [
        "                       # engine and control room, until Stop All Local or Ctrl-C",
        "--no-open              # print the control room's URL, open no browser",
        "--port 4848 -j 4       # somewhere other than 11000, four agents at a time",
        "--plan 005             # only plan 005, until stopped"
      ]

      # Exit status when Redis or the control room is not there to serve.
      UNAVAILABLE = 69

      # The progress log, echoed to the terminal: the terminal is where a
      # person watches `start` from when the page is closed, and it takes
      # no input.
      #
      # @param options [Hash]
      # @return [void]
      def call(**options)
        @rescan = Integer(options.fetch(:rescan, Engine::Dispatcher::RESCAN), exception: false)
        refuse("--rescan takes a whole number of seconds, at least 1.", 64) unless @rescan&.positive?

        tap = UI.tap_log(lambda { |message, fields|
          next if UI.quiet

          Kernel.warn(Engine::ProgressLog.render(message, **fields.slice(:plan, :status, :agent, :seconds, :round)))
        })
        super
      ensure
        UI.untap_log(tap) if tap
      end

      private

      # @param _options [Hash]
      # @param _web [OpenLanes::Web::Launcher]
      # @return [Hash]
      def staying(_options, _web) = { stay: true, rescan: @rescan }

      # @return [void]
      def without_live(message, _options)
        refuse("#{message}\n\nopenlanes start needs Redis: its control room is the only way to answer the " \
               "agents' questions. Start redis-server, or pass --redis-url. " \
               "`openlanes run` goes on without it, headless.",
          UNAVAILABLE)
      end

      # @return [void]
      def without_web(web, live, _options)
        live.close
        refuse("The control room did not answer on #{web.url}, and openlanes start is no use without it. " \
               "Its log: #{web.log}",
          UNAVAILABLE)
      end

      # A project with nothing left to do opens on the idea dialog (W19).
      #
      # @return [String]
      def browser_url(web, tree)
        open = tree.subjects.reject { Engine::Dispatcher::FINISHED.include?(it.status.key) }
        open.empty? ? "#{web.url}#start" : web.url
      end

      # What the service did, and exit 0: stopping it on purpose is not a
      # failure, and the failed attempts it lived through are listed above
      # the box.
      #
      # @return [void]
      def finish(runner, attempts, options, seconds:)
        puts ""
        puts attempt_lines(attempts)
        puts("", Engine.tally(attempts:, seconds:).render)
        unless quiet?(options)
          blocked = runner.blocked.map { it.feature.ordinal }
          lines = ["Stopped. Unfinished plans keep their state; openlanes start picks them up again."]
          lines << "Still waiting for answers: #{blocked.join(", ")}" unless blocked.empty?
          success("#{attempts.size} invocation#{"s" unless attempts.size == 1}, " \
                  "#{attempts.count(&:advanced?)} advanced\n\n#{lines.join("\n")}")
        end
        exit(0)
      end
    end
  end
end

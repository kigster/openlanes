# frozen_string_literal: true

module OpenLanes
  module Engine
    # `openlanes start` without the command: {RunWorkflow} as a long-lived
    # service. It stays up past every fixed point, rescanning the tree, and
    # treats a missing live board or control room as a refusal rather than a
    # reason to go on headless, since the page is the only way in.
    class StartWorkflow < RunWorkflow
      # Exit status when Redis or the control room is not there to serve.
      UNAVAILABLE = 69

      # @param rescan [Integer] seconds between rescans of .plans while idle
      # @param options [Hash] as for {RunWorkflow#initialize}
      def initialize(rescan:, **)
        super(**)
        @rescan = rescan
      end

      private

      # Without plans named, the whole tree.
      #
      # @return [Dry::Monads::Result] Success(nil)
      def unscoped = Success(nil)

      # The factory is this checkout's node on the board, unsuffixed.
      #
      # @return [nil]
      def node_role = nil

      # The factory claims a plan as it assigns it, not up front: it has no
      # list to claim, and a run that holds a plan it wants is simply a plan
      # it steps around.
      #
      # @return [Dry::Monads::Result] Success(nil)
      def held(_plans, _live) = Success(nil)

      # The control room (W1, W7): `openlanes web` as its own process beside
      # the engine, reading the board this run publishes.
      #
      # @param live [OpenLanes::Live::Session]
      # @return [Dry::Monads::Result] Success(OpenLanes::Web::Launcher), or a refusal
      def web_for(live)
        return Success(nil) if served_apart?

        web = launch_web(live)
        return Success(announced(web)) if web.ready?

        web.stop
        without_web(web, live)
      end

      # @param live [OpenLanes::Live::Session]
      # @return [OpenLanes::Web::Launcher] started, answering or not
      def launch_web(live)
        OpenLanes::Web.launcher(root: @root,
          plans_dir:   @tree.dir,
          port:        web_port,
          redis_url:   live.store.url,
          listen:      web_listen,
          credentials: @options[:credentials]).start
      end

      # Where the page is, in the startup box, and in the browser unless
      # `--no-open`.
      #
      # @param web [OpenLanes::Web::Launcher] answering
      # @return [OpenLanes::Web::Launcher] the same
      def announced(web)
        startup("Control room", web.port == web_port ? web.url : "#{web.url} (#{web_port} was taken)")
        startup("Also on", "#{(web_listen.urls(web.port) - [web.url]).join(", ")}, behind a login") if web_listen.public?
        OpenLanes::Web.open(browser_url(web)) unless @options[:open] == false
        web
      end

      # @return [Integer] the port asked for, which a busy one moves off
      def web_port = Integer(@options[:port] || OpenLanes::Web::DEFAULT_PORT)

      # @return [OpenLanes::Web::Listen]
      def web_listen = @options[:listen] || OpenLanes::Web::Listen.parse(nil)

      # `--no-web`: the page is another process's, `openlanes web` under
      # mprocs (`just start`) or, later, under the supervisor.
      #
      # @return [Boolean]
      def served_apart? = @options[:web] == false

      # @return [String]
      def stays_note
        return "The engine stays up for the control room `openlanes web` serves: Stop All Local or Ctrl-C ends it." if served_apart?

        "The engine stays up with its control room: Stop All Local or Ctrl-C ends it."
      end

      # Always stays, at the rescan asked for, and watches the pull requests
      # a person merges. `--rescan` is seconds
      # and the dispatcher counts ticks, so a 5 passed through unconverted
      # would rescan every 2.5 s.
      #
      # @param _web [OpenLanes::Web::Launcher]
      # @return [Hash]
      def staying(_web, _live = nil) = { stay: true, rescan: Dispatcher.ticks(@rescan), watch: watch }

      # @param message [String]
      # @return [Dry::Monads::Result::Failure]
      def without_live(message)
        refusal("#{message}\n\nopenlanes start needs Redis: its control room is the only way to answer the " \
                "agents' questions. Start redis-server, or pass --redis-url. " \
                "`openlanes run` goes on without it, headless.",
          UNAVAILABLE)
      end

      # @param web [OpenLanes::Web::Launcher]
      # @param live [OpenLanes::Live::Session]
      # @return [Dry::Monads::Result::Failure]
      def without_web(web, live)
        live.close
        refusal("The control room did not answer on #{web.url}, and openlanes start is no use without it. " \
                "Its log: #{web.log}",
          UNAVAILABLE)
      end

      # A project with nothing left to do opens on the idea dialog (W19).
      #
      # @param web [OpenLanes::Web::Launcher]
      # @return [String]
      def browser_url(web)
        open = @tree.subjects.reject { Dispatcher::FINISHED.include?(it.status.key) }
        open.empty? ? "#{web.url}#start" : web.url
      end

      # What the service did, and exit 0: stopping it on purpose is not a
      # failure, and the failed attempts it lived through are listed above
      # the box.
      #
      # @return [Integer] 0
      def finish(runner, attempts, seconds:)
        puts_report(attempts, Engine.tally(attempts:, seconds:).render)
        unless @quiet
          blocked = runner.blocked.map { it.feature.ordinal }
          lines = ["Stopped. Unfinished plans keep their state; openlanes start picks them up again."]
          lines << "Still waiting for answers: #{blocked.join(", ")}" unless blocked.empty?
          success("#{attempts.size} invocation#{"s" unless attempts.size == 1}, " \
                  "#{attempts.count(&:advanced?)} advanced\n\n#{lines.join("\n")}")
        end
        0
      end
    end
  end
end

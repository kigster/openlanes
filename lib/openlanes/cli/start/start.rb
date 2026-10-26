# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes start` — the factory (S1): a supervisor that runs the engine
    # (`openlanes engine --no-web`) and the control room (`openlanes web`) as
    # children, restarts whichever crashes, and stops both on `openlanes
    # stop`, Ctrl-C or SIGTERM. The engine ending of its own accord, on Stop
    # All Local or a refusal, ends the factory with the engine's status.
    #
    # It takes every flag the engine takes and hands the engine the ones
    # typed; the port, the listen addresses and the login are the page's.
    # `--background` starts the same factory detached from the terminal
    # (C1, S4), and returns once the page answers.
    class Start < EngineCommand
      desc "The factory: the engine and its control room, kept up until `openlanes stop`, Stop All Local or Ctrl-C"

      # Where `--background` sends what would have gone to the terminal (S4).
      LOG = File.join("log", "openlanes-start.log")

      # What the page needs to know before it starts.
      #
      # @!attribute [r] listen
      #   @return [Array<String>] the addresses it listens on
      # @!attribute [r] credentials
      #   @return [OpenLanes::Web::AdminAuth::Credentials, nil] its login, if any
      Page = Data.define(:listen, :credentials)

      option :background,
        type:    :boolean,
        default: false,
        desc:    "Detach from the terminal, write its output to #{LOG}, and return once the control room answers"

      example [
        "                       # engine and control room, until `openlanes stop`, Stop All Local or Ctrl-C",
        "--background           # the same, detached; prints the control room's URL",
        "--no-open              # print the control room's URL, open no browser",
        "--port 4848 -j 4       # somewhere other than 11000, four agents at a time",
        "--plan 005             # only plan 005, until stopped",
        "--no-web               # the engine alone, for a page `openlanes web` serves apart",
        "-I --admin-credentials admin:s3cret # the control room on every interface, behind a login"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        prepare(options)
        page = page_for(options)
        tree = tree_for(options)
        root = Dir.pwd
        supervisor_logging(options, root)
        running(Supervision.registration(Supervision::SUPERVISOR, root:).holder)
        web = launcher_for(options, root, tree, page)
        return background(options, root, page.credentials) if options[:background]

        exit(supervise(options, root, web))
      end

      private

      # @param options [Hash]
      # @return [void]
      def prepare(options)
        Supervision::Detached.leave_session
        quiet?(options)
        rescan_for(options)
      end

      # @param options [Hash]
      # @return [Page]
      def page_for(options)
        listen = listen_for(options)
        Page.new(listen:, credentials: credentials_for(options, listen))
      end

      # @param options [Hash]
      # @param root [String]
      # @return [void]
      def supervisor_logging(options, root)
        Log.setup(Log::Settings.from(options, root:), name: Supervision::SUPERVISOR)
      rescue Log::Invalid => e
        refuse(e.message, 64)
      end

      # @param holder [OpenLanes::Supervision::PidFile, nil]
      # @return [void]
      def running(holder)
        return unless holder

        refuse("The factory is already running here (pid #{holder.pid})#{" at #{holder.url}" if holder.url}.\n" \
               "`openlanes stop` stops it; `openlanes status` shows it.",
          75)
      end

      # The page's server, on the first free port from `--port`, fixed from
      # then on so a restart comes back at the same URL.
      #
      # @param options [Hash]
      # @param root [String]
      # @param tree [OpenLanes::Plans::Tree]
      # @param page [Page]
      # @return [OpenLanes::Web::Launcher, nil] nil under --no-web
      def launcher_for(options, root, tree, page)
        return if options[:web] == false

        launcher = OpenLanes::Web.launcher(root:,
          plans_dir:   tree.dir,
          port:        options.fetch(:port, OpenLanes::Web::DEFAULT_PORT),
          redis_url:   Live.redis_url(option: options[:redis_url]),
          listen:      page.listen,
          credentials: page.credentials)
        launcher.settle_port ? launcher : ports_taken(launcher)
      end

      # @param launcher [OpenLanes::Web::Launcher]
      # @return [void]
      def ports_taken(launcher)
        last = launcher.port + OpenLanes::Web::Launcher::PORTS_TRIED - 1
        refuse("Ports #{launcher.port}-#{last} are all taken. Pass --port to use another.", 69)
      end

      # @return [Integer] the exit status
      def supervise(options, root, web)
        registration = Supervision.registration(Supervision::SUPERVISOR, root:, url: web&.url)
        unwrap(registration.claim)
        programs = Programs.new(options:, defaults: self.class.default_params, root:).call(web)
        supervisor = Supervision.supervisor(programs:, registration:)
        %w[INT TERM].each { |name| Signal.trap(name) { supervisor.stop! } }
        announce(options, web)
        on_tick = opener(web) if web && options[:open]
        registration.hold { supervisor.call(&on_tick) }
      end

      # @param options [Hash]
      # @param web [OpenLanes::Web::Launcher, nil]
      # @return [void]
      def announce(options, web)
        say("Factory supervisor: pid #{::Process.pid}#{", control room at #{web.url}" if web}") unless quiet?(options)
      end

      # Opens the page once it first answers; a restarted server is not
      # opened again.
      #
      # @param web [OpenLanes::Web::Launcher]
      # @return [Proc]
      def opener(web)
        opened = false
        lambda do |_supervisor|
          next if opened || !OpenLanes::Web::Launcher.answering?(web.port)

          opened = true
          OpenLanes::Web.open(web.url)
        end
      end

      # Starts this same command again, detached, and waits for it to come
      # up. The login goes in the environment, never in argv, where `ps`
      # would show it.
      #
      # @param options [Hash]
      # @param root [String]
      # @param credentials [OpenLanes::Web::AdminAuth::Credentials, nil]
      # @return [void]
      def background(options, root, credentials)
        log = File.join(root, LOG)
        file = unwrap(Supervision.detached(root:).call(argv: restart(options),
          env: login(credentials),
          log:,
          web: options[:web] != false))
        say("The factory is running in the background (pid #{file.pid}); its output goes to #{log}.") unless UI.quiet
        puts(file.url) if file.url
      end

      # @param options [Hash]
      # @return [Array<String>] this command, with the flags typed but the login
      def restart(options)
        flags = Argv.for(self.class.options, options, defaults: self.class.default_params, except: %i[background admin_credentials])
        [OpenLanes::Web::Launcher::EXE, "start", *flags]
      end

      # @param credentials [OpenLanes::Web::AdminAuth::Credentials, nil]
      # @return [Hash{String => String}]
      def login(credentials)
        return {} unless credentials

        { OpenLanes::Web::AdminAuth::ENV_NAME => "#{credentials.user}:#{credentials.password}" }
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes web` — the control room's API server on its own. `openlanes run`
    # starts one beside the engine; this is that server, and with `--demo`
    # the same server over a pretend engine, for Cypress and front-end work.
    class Web < Base
      desc "Serve the control room page and its API on 127.0.0.1"

      option :port,
        default: OpenLanes::Web::DEFAULT_PORT.to_s,
        desc:    "Port to listen on"
      option :redis_url,
        desc: "Redis the engine publishes to (default: $OPENLANES_REDIS_URL, else .openlanes.yml redis_url, else $REDIS_URL, " \
              "else #{Live::DEFAULT_URL})"
      option :open,
        type:    :boolean,
        default: true,
        desc:    "Open the page in the browser; --no-open prints the URL only"
      option :demo,
        type:    :boolean,
        default: false,
        desc:    "Serve a sample run that moves and answers commands, with no agents. " \
                 "Uses Redis when it answers, an in-memory store when it does not"
      option :identity,
        desc: "With --demo: register as USER@HOST instead of this login and host, so a second demo on " \
              "another port is another machine on the same Redis"

      example [
        "                 # serve the live run of this checkout",
        "--demo --no-open # the sample run, for Cypress and npm run dev",
        "--port 4848      # somewhere other than 11000",
        "--demo --port 11101 --identity demo@second-machine # a second machine for the chat"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        tree = tree_for(options)
        root = File.dirname(tree.dir)
        url = Live.redis_url(option: redis_url_option(options), config: Config.current)
        node = node_for(root, options)
        stores = stores_for(url, options)
        keys = Live.keys(root:, node:)
        keys = keys.with(repo: "demo/#{keys.repo}") if options[:demo]
        demo = OpenLanes::Web.demo(store: stores.current, keys:, node: declared(node, options)).start if options[:demo]
        copilot = demo ? OpenLanes::Web::Demo::COPILOT : copilot_for(root:, tree:, stores:, keys:)
        context = OpenLanes::Web.context(stores:, keys:, plans_dir: tree.dir, url: stores.current.url, node:, demo:, copilot:)
        server = OpenLanes::Web.server(app: OpenLanes::Web.app(context), context:, port: options[:port])
        serve(server, options, keys:, node:, url: stores.current.url)
      ensure
        demo&.stop
        copilot.stop if copilot.respond_to?(:stop)
      end

      private

      # `--redis-url`, else the URL `openlanes run` hands its server through the
      # environment, so a password never shows in `ps`. Both are passed to
      # {Live.redis_url} as the option, which keeps the rest of its order.
      #
      # @param options [Hash]
      # @param env [Hash]
      # @return [String, nil]
      def redis_url_option(options, env: ENV)
        [options[:redis_url], env[OpenLanes::Web::Launcher::REDIS_URL_ENV]].find { !it.to_s.strip.empty? }
      end

      # This machine, or under `--demo` the one `--identity` declares. A live
      # server is refused one: its node id is what claims and commands are
      # keyed by, and a run under a borrowed name would answer for a machine
      # it is not.
      #
      # @param root [String]
      # @param options [Hash]
      # @return [OpenLanes::Live::Node]
      def node_for(root, options)
        identity = options[:identity].to_s.strip
        return Live::Node.current(root:) if identity.empty?

        refuse("--identity is for the demo only; pass --demo with it.", 64) unless options[:demo]
        Live::Node.declared(identity, root:)
      rescue Live::Node::Invalid => e
        refuse("--identity: #{e.message}", 64)
      end

      # @return [OpenLanes::Live::Node, nil] the node the demo publishes as, when declared
      def declared(node, options) = options[:identity].to_s.strip.empty? ? nil : node

      # @return [OpenLanes::Web::Stores]
      def stores_for(url, options)
        store = Live.connect(url)
        store.close
        OpenLanes::Web::Stores.new { Live.store(url) }
      rescue Live::Unavailable => e
        unless options[:demo]
          refuse("#{e.message}\n\nThe page reads the run from Redis. Start redis-server, pass --redis-url, " \
                 "or try --demo.",
            69)
        end
        warn("#{e.message}\n\nThe demo keeps its board in memory instead: this page only, no other machine.") unless quiet?(options)
        OpenLanes::Web::Stores.shared(Live.memory_store)
      end

      # c3po-operator, answering in this server (W17). It runs beside the
      # page rather than in the engine so it answers with no run going too.
      #
      # @return [OpenLanes::Live::Copilot::Operator]
      def copilot_for(root:, tree:, stores:, keys:)
        Live::Copilot::Operator.new(root:, plans_dir: tree.dir, stores:, keys:)
      end

      # Listen until INT or TERM.
      #
      # @return [void]
      def serve(server, options, keys:, node:, url:)
        begin
          server.start
        rescue Errno::EADDRINUSE
          refuse("Port #{options[:port]} is taken: another `openlanes web` may already be serving. " \
                 "Pass --port to use another.",
            69)
        end
        %w[INT TERM].each { |name| Signal.trap(name) { Thread.new { server.stop } } }
        unless quiet?(options)
          info("Control room: #{server.url}#{" (demo)" if options[:demo]}\n" \
               "Redis: #{Live.mask(url)} as #{node.label} (#{keys.node}), repository #{keys.repo}")
        end
        OpenLanes::Web.open(server.url) if options[:open]
        server.wait
      end
    end
  end
end

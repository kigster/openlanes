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

      example [
        "                 # serve the live run of this checkout",
        "--demo --no-open # the sample run, for Cypress and npm run dev",
        "--port 4848      # somewhere other than 11000"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        tree = tree_for(options)
        root = File.dirname(tree.dir)
        url = Live.redis_url(option: redis_url_option(options), config: Config.current)
        stores = stores_for(url, options)
        node = Live::Node.current(root:)
        keys = Live.keys(root:, node:)
        keys = keys.with(repo: "demo/#{keys.repo}") if options[:demo]
        demo = OpenLanes::Web.demo(store: stores.current, keys:).start if options[:demo]
        context = OpenLanes::Web.context(stores:, keys:, plans_dir: tree.dir, url: stores.current.url, node:, demo:)
        server = OpenLanes::Web.server(app: OpenLanes::Web.app(context), context:, port: options[:port])
        serve(server, options, keys:, node:, url: stores.current.url)
      ensure
        demo&.stop
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

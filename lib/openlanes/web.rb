# frozen_string_literal: true

require "rbconfig"
require "securerandom"

module OpenLanes
  # The control room's API server (plan 004, W3, W7): Sinatra on a threaded
  # Puma, bound to 127.0.0.1. It holds no run state. Everything it shows is
  # read from Redis through {Live}, and everything it is told goes back
  # there as a command for the engine, so a restarted server loses nothing.
  #
  #   context = Web.context(stores:, keys:, plans_dir:, url:)
  #   server  = Web.server(app: Web.app(context), context:, port: 11000).start
  #   server.wait
  module Web
    # Where the gem is, whether run from a checkout or installed.
    GEM_ROOT = File.expand_path("../..", __dir__)

    # The built page, which the gem ships (W3).
    DIST = File.join(GEM_ROOT, "web", "dist")

    # The sample board the page's own tests type-check, and {Demo} replays.
    FIXTURE = File.join(GEM_ROOT, "web", "src", "api", "fixtures", "board.json")

    # Where the server listens unless told otherwise (contract.md).
    DEFAULT_PORT = 11_000

    # Loopback by default: the page can stop agents and has no login, so
    # nothing off this machine reaches it unless `--ips` or `-I` says so (W3).
    HOST = "127.0.0.1"

    module_function

    # @param stores [OpenLanes::Web::Stores]
    # @param keys [OpenLanes::Live::Keys]
    # @param plans_dir [String] absolute path of the `.plans` directory
    # @param url [String] the Redis address, shown masked by `/healthz`
    # @param rest [Hash] {Context}'s other fields
    # @return [OpenLanes::Web::Context]
    def context(stores:, keys:, plans_dir:, url:, **rest)
      rest[:chat] ||= chat(stores:, keys:, node: rest[:node])
      Context.new(stores:, keys:, plans_dir:, url:, csrf: SecureRandom.hex(32), **rest)
    end

    # The chat between machines for one server (plan 006). Its machine is
    # the node id in +keys+, so it answers for the same machine the board does.
    #
    # @param stores [OpenLanes::Web::Stores]
    # @param keys [OpenLanes::Live::Keys]
    # @param node [OpenLanes::Live::Node, nil]
    # @return [OpenLanes::Live::Chat]
    def chat(stores:, keys:, node: nil, **)
      machine = keys.node.split(":").first
      Live::Chat.new(stores:, keys:, machine:, label: node&.label || machine, **)
    end

    # The routes, with every request logged on the way out (see {RequestLog}).
    #
    # @param context [OpenLanes::Web::Context]
    # @return [#call] a Rack application
    def app(context) = RequestLog.new(App.serving(context))

    # @param app [#call]
    # @param context [OpenLanes::Web::Context]
    # @param port [Integer]
    # @return [OpenLanes::Web::Server]
    def server(app:, context:, port: DEFAULT_PORT, **) = Server.new(app:, context:, port:, **)

    # @return [OpenLanes::Web::Demo]
    def demo(**) = Demo.new(**)

    # @return [OpenLanes::Web::Launcher]
    def launcher(**) = Launcher.new(**)

    # Whether a browser can be opened here (W1): not under CI, not over
    # SSH, not without a terminal, and on Linux only with a display.
    #
    # @param env [Hash]
    # @param tty [Boolean] whether a person is at the terminal
    # @param os [String] `RbConfig::CONFIG["host_os"]`
    # @return [Boolean]
    def display?(env: ENV, tty: $stderr.tty?, os: RbConfig::CONFIG["host_os"])
      return false if !tty || present?(env["CI"]) || present?(env["SSH_CONNECTION"]) || present?(env["SSH_TTY"])
      return true if os.match?(/darwin|mswin|mingw/)

      present?(env["DISPLAY"]) || present?(env["WAYLAND_DISPLAY"])
    end

    # Open +url+ in the browser, when there is one to open.
    #
    # @param url [String]
    # @param display [Boolean]
    # @return [Boolean] whether a browser was asked to open it
    def open(url, display: display?)
      return false unless display

      require "launchy"
      Launchy.open(url)
      true
    rescue Launchy::Error, SystemCallError
      false
    end

    # @return [Boolean]
    def present?(value) = !value.to_s.strip.empty?
  end
end

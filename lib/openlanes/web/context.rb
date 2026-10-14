# frozen_string_literal: true

require "concurrent/atomic/atomic_boolean"

module OpenLanes
  module Web
    # Everything one API server knows, fixed when it starts: where Redis is,
    # whose keys it reads, the token every write must carry, and how often
    # the event stream looks for news.
    #
    # @!attribute [r] stores
    #   @return [OpenLanes::Web::Stores] a store per request thread
    # @!attribute [r] keys
    #   @return [OpenLanes::Live::Keys] this node's
    # @!attribute [r] plans_dir
    #   @return [String] the `.plans` directory plan files are read from
    # @!attribute [r] url
    #   @return [String] the Redis address
    # @!attribute [r] csrf
    #   @return [String] what `X-CSRF-Token` must equal
    # @!attribute [r] dist
    #   @return [String] the built page
    # @!attribute [r] node
    #   @return [OpenLanes::Live::Node, nil] this machine, for `/api/session`
    #     while no engine has published a snapshot
    # @!attribute [r] tick
    #   @return [Float] seconds between the event stream's looks (contract: 250 ms)
    # @!attribute [r] ping_every
    #   @return [Float] seconds between `: ping` comments
    # @!attribute [r] lifetime
    #   @return [Float, nil] seconds an event stream lives; nil for as long as
    #     the browser holds it. The suite sets one so a stream ends.
    # @!attribute [r] demo
    #   @return [OpenLanes::Web::Demo, nil] the demo engine, under `--demo`,
    #     which `POST /api/demo/reset` puts back to the start
    # @!attribute [r] copilot
    #   @return [#call, nil] who answers the copilot's messages (W17):
    #     {Live::Copilot::Operator} beside a real run, {Demo::COPILOT} under
    #     `--demo`, nil where nothing does, and `POST /api/copilot` says so
    # @!attribute [r] background
    #   @return [#call] runs the block it is given apart from the request, a
    #     thread by default; the suite passes one that runs it when told
    # @!attribute [r] chat
    #   @return [OpenLanes::Live::Chat, nil] the chat between machines (plan 006),
    #     relayed to this server's pages; nil where nothing serves it
    # @!attribute [r] stopping
    #   @return [Concurrent::AtomicBoolean] set when the server shuts down, so
    #     open streams end within a tick
    Context = Data.define(:stores,
      :keys,
      :plans_dir,
      :url,
      :csrf,
      :dist,
      :node,
      :tick,
      :ping_every,
      :lifetime,
      :demo,
      :copilot,
      :background,
      :chat,
      :stopping) do
      def initialize(dist: DIST, node: nil, tick: 0.25, ping_every: 15.0, lifetime: nil, demo: nil, copilot: nil, chat: nil,
        background: Context::THREAD, stopping: Concurrent::AtomicBoolean.new, **rest)
        super
      end

      # @return [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore] this thread's
      def store = stores.current

      # @return [String] the page's entry point
      def index = File.join(dist, "index.html")

      # @return [Boolean]
      def dist? = File.file?(index)
    end

    class Context
      # Work started apart from a request, on a thread of its own.
      THREAD = ->(&work) { Thread.new(&work) }
    end
  end
end

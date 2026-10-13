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
      :stopping) do
      def initialize(dist: DIST, node: nil, tick: 0.25, ping_every: 15.0, lifetime: nil, demo: nil,
        stopping: Concurrent::AtomicBoolean.new, **rest)
        super
      end

      # @return [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore] this thread's
      def store = stores.current

      # @return [String] the page's entry point
      def index = File.join(dist, "index.html")

      # @return [Boolean]
      def dist? = File.file?(index)
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Live
    # One engine's live run: its node and keys, its claims, the publisher
    # that writes its board and the reader that applies its commands, built
    # once and handed to the runner.
    #
    #   live = Live.session(store:, root:, tree:, agents:)
    #   runner = Engine.runner(..., on_board: live.on_board, claims: live.claims)
    #   runner.call { |dispatcher| live.attach(dispatcher) }
    #   live.close
    class Session
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param root [String] the checkout
      # @param tree [OpenLanes::Plans::Tree]
      # @param agents [OpenLanes::Agents::Registry]
      # @param project [String, nil] the header's name (W18); the root's name by default
      # @param node [OpenLanes::Live::Node]
      # @param repo [String]
      # @param clock [Proc] wall time
      def initialize(store:, root:, tree:, agents:, project: nil, node: Node.current(root:), repo: Repo.for(root),
        clock: -> { Time.now })
        @store = store
        @node = node
        @keys = Keys.new(repo:, node: node.name)
        @run_state = RunState.new
        @record = RunRecord.new(store:, keys: @keys, run_state: @run_state)
        @claims = Claims.new(store:, keys: @keys)
        @publisher = Publisher.new(store:,
          keys: @keys,
          node:,
          tree:,
          agents:,
          claims: @claims,
          run_state: @run_state,
          project: project || File.basename(root),
          clock:)
        @commands = Commands.new(store:,
          keys: @keys,
          node:,
          run_state: @run_state,
          record: @record,
          claims: @claims,
          clock:)
      end

      # @return [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      attr_reader :store

      # @return [OpenLanes::Live::Node]
      attr_reader :node

      # @return [OpenLanes::Live::Keys]
      attr_reader :keys

      # @return [OpenLanes::Live::Claims]
      attr_reader :claims

      # @return [OpenLanes::Live::Publisher]
      attr_reader :publisher

      # @return [OpenLanes::Live::Commands]
      attr_reader :commands

      # @return [OpenLanes::Live::RunState]
      attr_reader :run_state

      # @return [OpenLanes::Live::RunRecord]
      attr_reader :record

      # @return [Proc] the runner's `on_board:`
      def on_board = @publisher.to_proc

      # Wire the run in: the run state a previous engine left is taken back
      # on the first tick, commands are applied at the top of each tick, mail
      # published to Redis is drained into the plans' `state.json`, and the
      # log is heard from now on.
      #
      # @param dispatcher [OpenLanes::Engine::Dispatcher]
      # @return [void]
      def attach(dispatcher)
        @publisher.listen
        @publisher.on_lost { |ordinals| dispatcher.fence(ordinals) }
        dispatcher.before_tick(&@record)
        dispatcher.before_tick(&@commands)
        dispatcher.mail = Mail.new(store: @store, keys: @keys)
      end

      # The run is over: the run state is written down, claims go back, and
      # this node's snapshot goes at once rather than when it expires, so
      # other pages stop showing it.
      #
      # @return [void]
      def close
        @record.close
        @publisher.close
        @claims.release_all
        @store.del(@keys.snapshot)
        @store.hdel(@keys.nodes, @node.name)
      rescue Unavailable
        nil
      end

      # @return [String] where, with the password masked, and as whom
      def describe = described.join(" ")

      # The same, in the two parts a narrow box may break it between: the
      # node id is long, and wraps mid-word when left to the box.
      #
      # @return [Array(String, String)] `"redis://… as kig@host"` and `"(<node id>)"`
      def described = ["#{Live.mask(@store.url)} as #{@node.label}", "(#{@node.name})"]
    end
  end
end

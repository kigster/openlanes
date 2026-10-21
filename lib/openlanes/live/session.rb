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
      # @param outage [OpenLanes::Live::Outage] what pauses the run while
      #   Redis is gone; a spec hands in one on its own clock
      def initialize(store:, root:, tree:, agents:, project: nil, node: Node.current(root:), repo: Repo.for(root),
        clock: -> { Time.now }, outage: Outage.new(store:, limit: Config.current.outage_limit))
        @store = store
        @node = node
        @keys = Keys.new(repo:, node: node.name)
        @run_state = RunState.new
        @record = RunRecord.new(store:, keys: @keys, run_state: @run_state)
        @outage = outage
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

      # @return [OpenLanes::Live::Outage]
      attr_reader :outage

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
        # First, so a tick that finds Redis gone pauses before anything else
        # on it asks Redis for something (W32).
        dispatcher.before_tick(&@outage)
        dispatcher.before_tick(&@record)
        dispatcher.before_tick(&@commands)
        dispatcher.mail = Mail.new(store: @store, keys: @keys)
        @outage.on_resume { recover(it) }
      end

      # Redis answers again: say how long it was gone and which copy of the
      # run state won, and publish that as `run.outage`.
      #
      # @param window [OpenLanes::Live::Outage::Window]
      # @return [OpenLanes::Live::OutageReport]
      def recover(window)
        report = OutageReport.new(store: @store,
          keys: @keys,
          node: @node,
          window:,
          reconciled_from: @record.reconcile)
        UI.log(report.line)
        @publisher.outage = report.to_h
        report
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

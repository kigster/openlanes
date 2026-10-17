# frozen_string_literal: true

require "json"

module OpenLanes
  module Live
    # The engine's side of the board (W13): handed each tick's
    # {Engine::Board} as the runner's `on_board`, it writes the snapshot,
    # appends it to the board stream, refreshes this node's heartbeat and
    # renews its claims.
    #
    # It also keeps the latest log lines for the page, by tapping {UI.log}
    # rather than asking callers to log twice.
    #
    # A Redis that goes away mid-run is reported once and otherwise
    # ignored: the run is the agents' work, and the page is a view of it.
    class Publisher
      # Log lines a snapshot carries.
      LOG_LINES = 200

      # Words in a log line that mark it as something gone wrong.
      PROBLEMS = /\b(?:fail(?:ed|ure)?|error|refused|unavailable|died)\b/i

      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @param node [OpenLanes::Live::Node]
      # @param tree [OpenLanes::Plans::Tree]
      # @param agents [OpenLanes::Agents::Registry]
      # @param project [String]
      # @param claims [OpenLanes::Live::Claims, nil]
      # @param run_state [OpenLanes::Live::RunState]
      # @param description [String, nil]
      # @param clock [Proc] wall time
      def initialize(store:, keys:, node:, tree:, agents:, project:, claims: nil, run_state: RunState.new,
        description: nil, clock: -> { Time.now })
        @store = store
        @keys = keys
        @node = node
        @tree = tree
        @agents = agents
        @project = project
        @claims = claims
        @run_state = run_state
        @description = description
        @clock = clock
        @meter = Meter.new
        @log = []
        @log_mutex = Mutex.new
        @seq = nil
        @warned = false
        @on_lost = nil
      end

      # What to do with plans whose claim lapsed and went to another node:
      # the session stops their agents, so two machines never work one plan.
      #
      # @yieldparam ordinals [Array<String>]
      # @return [void]
      def on_lost(&block)
        @on_lost = block
      end

      # @return [OpenLanes::Live::Meter]
      attr_reader :meter

      # @return [Integer, nil] the last sequence number published
      attr_reader :seq

      # @return [Proc] for {Engine::Runner}'s `on_board:`
      def to_proc = method(:call).to_proc

      # @param board [OpenLanes::Engine::Board]
      # @return [Hash, nil] the snapshot published, nil when Redis was not there
      def call(board)
        now = @clock.call
        @started_at ||= now - (UI.monotonic - board.started_at)
        @meter.record(board.rows, now:)
        snapshot = build(board, now)
        json = JSON.generate(snapshot)
        @store.multi do |tx|
          tx.set(@keys.snapshot, json, ex: Keys::SNAPSHOT_TTL)
          tx.xadd(@keys.board, { seq: snapshot[:seq], json: }, maxlen: Keys::BOARD_LENGTH)
          tx.hset(@keys.nodes, @node.name, JSON.generate(@node.wire(heartbeat_at: now)))
        end
        nudge(snapshot)
        lost = @claims&.renew || []
        unless lost.empty?
          UI.log("claims lost to another machine: #{lost.join(", ")}; stopping their agents")
          @on_lost&.call(lost)
        end
        @warned = false
        snapshot
      rescue Unavailable => e
        unavailable(e)
        nil
      end

      # Start keeping {UI.log}'s lines.
      #
      # @return [void]
      def listen
        return if @tap

        @tap = UI.tap_log(method(:hear))
      end

      # Stop keeping them.
      #
      # @return [void]
      def close
        UI.untap_log(@tap) if @tap
        @tap = nil
      end

      # One log line, as the page shows it. Public so a component that does
      # not go through {UI.log} can still be heard.
      #
      # @param message [String]
      # @param fields [Hash] `plan:`, `agent:` and the rest of {UI.log}'s columns
      # @param source [String, nil]
      # @param level [String, nil]
      # @return [void]
      def hear(message, fields = {}, source: nil, level: nil)
        line = { at:     @clock.call.utc.iso8601,
                 source: source || fields[:agent]&.to_s || "engine",
                 level:  level || (message.to_s.match?(PROBLEMS) ? "warn" : "info"),
                 text:   message.to_s,
                 plan:   fields[:plan]&.to_s }
        @log_mutex.synchronize do
          @log << line
          @log.shift(@log.size - LOG_LINES) if @log.size > LOG_LINES
        end
      end

      # @return [Array<Hash>] the lines kept, newest last
      def log = @log_mutex.synchronize { @log.dup }

      private

      # @param board [OpenLanes::Engine::Board]
      # @param now [Time]
      # @return [Hash]
      def build(board, now)
        Snapshot.new(board:,
          tree:        @tree,
          agents:      @agents,
          node:        @node,
          repo:        @keys.repo,
          project:     @project,
          description: @description,
          seq:         next_seq,
          at:          now,
          started_at:  @started_at,
          claims:      @claims,
          run_state:   @run_state,
          meter:       @meter,
          log:).to_h
      end

      # Fields that move with the clock alone: the sequence number, the
      # snapshot's time, this node's heartbeat, and how long each plan has
      # been worked on. A car's `elapsed` is left in on purpose: while an
      # agent runs, its seconds counter is what the page is there to show.
      #
      # @param snapshot [Hash]
      # @return [Hash] what the page would see change
      def content(snapshot)
        snapshot.except(:seq, :at)
                .merge(node:  snapshot[:node].except(:heartbeat_at),
                  plans: Array(snapshot[:plans]).map { it.except(:elapsed) })
      end

      # Nudges the open pages ({News}) when this tick's snapshot says
      # something the last one did not. The snapshot is still written every
      # tick, because its expiry is how a node is known to be alive; only
      # the nudge waits for news, so an engine with nothing to do is quiet.
      #
      # @param snapshot [Hash]
      # @return [void]
      def nudge(snapshot)
        now = content(snapshot)
        return if now == @published

        News.publish(store: @store, keys: @keys, kind: "board")
        @published = now
      end

      # One more than the last published, even across an engine restart:
      # the API server reads a change of `seq` as news, and a restart that
      # counted from one again would look like the past.
      #
      # @return [Integer]
      def next_seq
        @seq ||= @store.xrevrange(@keys.board, count: 1).first&.fields&.fetch("seq", nil).to_i
        @seq += 1
      end

      # @param error [OpenLanes::Live::Unavailable]
      # @return [void]
      def unavailable(error)
        return if @warned

        @warned = true
        UI.log("board not published: #{error.message}")
      end
    end
  end
end

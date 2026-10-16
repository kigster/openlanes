# frozen_string_literal: true

require "json"

module OpenLanes
  module Web
    # `openlanes web --demo`: an engine with no agents. Every second it publishes
    # a {DemoBoard} snapshot for this node and for one pretend other machine,
    # through the same keys and in the same shape as {Live::Publisher}, and
    # it answers the page's commands as {Live::Commands} does: read through
    # the `engine` group, applied once, a `done` or `refused` reply written
    # to `replies` and `done`, then acknowledged.
    #
    # Cypress and the front end's dev server run against it.
    class Demo
      # Seconds between snapshots.
      INTERVAL = 1.0

      # The other machine's checkout id, fixed so its keys are stable.
      OTHER_CHECKOUT = Live::Node.digest("openlanes-demo-other", Live::Node::CHECKOUT_LENGTH)

      # What the copilot answers in the demo, where no agent runs and the
      # board is made up: one plain line, so the panel can still be tried.
      COPILOT_TEXT = "This is the demo run: c3po-operator does not run here, so nothing reads this or acts on it."

      # The copilot's responder under `--demo` (W17), in place of
      # {Live::Copilot::Operator}.
      COPILOT = lambda do |turn|
        [Live::Copilot::Turn.new(id: "#{turn.id}.1", from: "copilot", kind: "text", text: COPILOT_TEXT)]
      end

      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys] this node's
      # @param board [OpenLanes::Web::DemoBoard, nil] the fixture's, by default
      # @param node [OpenLanes::Live::Node, nil] a declared identity
      #   (`--identity`), which the board, and every reset of it, is published as
      # @param interval [Float]
      # @param clock [Proc] wall time
      def initialize(store:, keys:, board: nil, node: nil, interval: INTERVAL, clock: -> { Time.now })
        @store = store
        @keys = keys
        @node = node
        @board = board || DemoBoard.new(node:)
        @interval = interval
        @clock = clock
        @seqs = {}
        @ready = false
        @running = false
        @mutex = Mutex.new
      end

      # @return [OpenLanes::Web::DemoBoard]
      def board = @mutex.synchronize { @board }

      # Back to the fixture as it was, so each Cypress spec starts from the
      # same board whatever the last one answered or stopped.
      #
      # @return [void]
      def reset = @mutex.synchronize { @board = DemoBoard.new(node: @node) }

      # Publish and answer every {INTERVAL}, on a thread of its own.
      #
      # @return [self]
      def start
        @running = true
        @thread = Thread.new do
          while @running
            tick
            sleep @interval
          end
        end
        self
      end

      # Stop, and take this demo's snapshots down so no page shows them.
      #
      # @return [void]
      def stop
        @running = false
        @thread&.join(@interval * 2)
        names = [@keys.node, other].compact
        @store.del(*names.map { @keys.snapshot(it) })
        @store.hdel(@keys.nodes, *names)
      rescue Live::Unavailable
        nil
      end

      # One second: commands first, as the engine applies them at the top of
      # its tick, then the board moves and is published.
      #
      # @return [Array<OpenLanes::Live::Reply>] the commands answered
      def tick
        @mutex.synchronize do
          replies = commands
          @board.advance(@clock.call)
          publish(@keys.node, @board.me)
          @board.others.each { publish(other, it) }
          replies
        end
      rescue Live::Unavailable => e
        UI.log("demo: #{e.message}")
        []
      end

      private

      # @return [String, nil] the pretend other machine's node name, when this demo has one
      def other = @board.others.first&.dig("node", "id")&.then { "#{it}:#{OTHER_CHECKOUT}" }

      # @return [void]
      def publish(name, snapshot)
        snapshot["seq"] = next_seq(name)
        # The fixture names a Redis for the page to show; the demo says the
        # one it is really publishing through, as the engine does.
        snapshot["redis_url"] = Live.redact(@store.url)
        json = JSON.generate(snapshot)
        @store.multi do |tx|
          tx.set(@keys.snapshot(name), json, ex: Live::Keys::SNAPSHOT_TTL)
          tx.xadd(@keys.board(name), { seq: snapshot["seq"], json: }, maxlen: Live::Keys::BOARD_LENGTH)
          tx.hset(@keys.nodes, name, JSON.generate(snapshot["node"]))
        end
      end

      # Carries on from the last seq in the stream, as the engine does, so a
      # restarted demo never looks like the past to an open page.
      #
      # @return [Integer]
      def next_seq(name)
        @seqs[name] ||= @store.xrevrange(@keys.board(name), count: 1).first&.fields&.fetch("seq", nil).to_i
        @seqs[name] += 1
      end

      # @return [Array<OpenLanes::Live::Reply>]
      def commands
        unless @ready
          # "$": commands left in the stream by an earlier demo were meant for
          # a board that no longer exists.
          @store.xgroup_create(@keys.commands, Live::Keys::GROUP, from: "$")
          @ready = true
        end
        @store.xreadgroup(@keys.commands, Live::Keys::GROUP, @keys.node, id: ">", count: Live::Commands::BATCH)
              .map { answer(it) }
      end

      # @param entry [OpenLanes::Live::Store::Entry]
      # @return [OpenLanes::Live::Reply]
      def answer(entry)
        command = Live::Command.parse(entry.fields["json"].to_s)
        first = @store.hget(@keys.done, command.id)
        reply = first ? parse(first) : outcome(command)
        @store.multi do |tx|
          tx.hset(@keys.done, reply.id, reply.to_json) unless first
          tx.xadd(@keys.replies, { json: reply.to_json }, maxlen: Live::Keys::REPLIES_LENGTH)
          tx.xack(@keys.commands, Live::Keys::GROUP, entry.id)
        end
        reply
      rescue Live::Command::Invalid => e
        refuse(entry, e.message)
      end

      # @return [OpenLanes::Live::Reply]
      def outcome(command)
        reason = @board.apply(command)
        Live::Reply.new(id: command.id, status: "done", reason: reason.is_a?(String) ? reason : nil, at: @clock.call)
      rescue DemoBoard::Refusal => e
        Live::Reply.new(id: command.id, status: "refused", reason: e.message, at: @clock.call)
      end

      # @return [OpenLanes::Live::Reply]
      def refuse(entry, reason)
        reply = Live::Reply.new(id: entry.id, status: "refused", reason:, at: @clock.call)
        @store.multi do |tx|
          tx.xadd(@keys.replies, { json: reply.to_json }, maxlen: Live::Keys::REPLIES_LENGTH)
          tx.xack(@keys.commands, Live::Keys::GROUP, entry.id)
        end
        reply
      end

      # @return [OpenLanes::Live::Reply]
      def parse(json)
        data = JSON.parse(json)
        Live::Reply.new(id: data["id"], status: data["status"], reason: data["reason"], at: Time.iso8601(data["at"]))
      end
    end
  end
end

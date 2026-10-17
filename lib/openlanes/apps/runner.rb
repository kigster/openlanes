# frozen_string_literal: true

require "concurrent/atomic/atomic_boolean"
require "json"

module OpenLanes
  module Apps
    # `openlanes app start` in the foreground (plan 012, B6): one plan's app
    # started, kept, and stopped.
    #
    # Each tick it heartbeats the app's statuses into Redis for the Preview
    # tab ({Listing}), restarts the processes whose `restart_on` files
    # changed ({Watcher}), and applies what the tab's toolbar asked for
    # (`Live::Keys#app_commands`). It ends on INT or TERM, which is what
    # `openlanes app stop` sends, or on the toolbar's Stop, and either way
    # stops every process and takes the app off the board.
    #
    # Redis is optional. Without a store the app runs just the same and the
    # page simply never hears of it.
    class Runner
      # Seconds between ticks: the watcher's poll and the heartbeat.
      INTERVAL = 1

      # Commands kept on the stream; the runner reads only what arrives
      # after it started, so this is only a bound on Redis.
      COMMANDS_LENGTH = 100

      # What the toolbar may ask for.
      ACTIONS = %w[restart stop].freeze

      # @param definition [OpenLanes::Apps::Definition]
      # @param root [String] the checkout
      # @param plan [String]
      # @param branch [String]
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore, nil]
      # @param keys [OpenLanes::Live::Keys, nil]
      # @param interval [Numeric]
      # @param sleeper [#call] waits the given seconds
      # @param stopping [Concurrent::AtomicBoolean] set to end the loop
      # @param say [#call] given a line for the terminal
      # @param supervisor [Hash] more arguments for {Supervisor.new}
      def initialize(definition:, root:, plan:, branch:, store: nil, keys: nil, interval: INTERVAL,
        sleeper: ->(seconds) { sleep seconds }, stopping: Concurrent::AtomicBoolean.new, say: ->(_) {}, supervisor: {})
        @definition = definition
        @plan = plan
        @store = store
        @keys = keys
        @interval = interval
        @sleeper = sleeper
        @stopping = stopping
        @say = say
        @supervisor = Supervisor.new(definition:, root:, plan:, branch:, publisher: method(:publish), **supervisor)
        @watcher = Watcher.new(root:, definition:)
      end

      # @return [OpenLanes::Apps::Supervisor]
      attr_reader :supervisor

      # @return [Concurrent::AtomicBoolean]
      attr_reader :stopping

      # Start the app and keep it until told to stop.
      #
      # @return [void]
      # @raise [OpenLanes::Apps::Supervisor::StartFailed] after the failed
      #   statuses were published, so the tab can show why
      def call
        cursor = newest_command
        @supervisor.start
        until @stopping.true?
          @watcher.changed.each { restart(it, why: "its files changed") }
          cursor = commands(cursor)
          heartbeat
          @sleeper.call(@interval) unless @stopping.true?
        end
      rescue Supervisor::StartFailed
        # The failed statuses stay on the board until their heartbeat runs
        # out, so the tab can say why before it goes.
        failed = true
        raise
      ensure
        @supervisor.stop
        live { Listing.remove(store: @store, keys: @keys, plan: @plan) } unless failed
        nudge
      end

      # The supervisor's publisher: every transition goes out at once, with
      # the whole app, since the page reads a plan's processes together.
      #
      # @param status [OpenLanes::Apps::Status]
      # @return [void]
      def publish(status)
        @say.call("#{status.process} #{status.state} on port #{status.port}#{": #{status.reason}" if status.reason}")
        heartbeat
        nudge
      end

      private

      # @return [void]
      def heartbeat = live { Listing.write(store: @store, keys: @keys, plan: @plan, statuses: @supervisor.statuses) }

      # Tells open pages the app changed. Only on a transition or a stop,
      # never on the once-a-second {#heartbeat}, which changes nothing a
      # page shows: an app that is merely up keeps every stream asleep.
      #
      # @return [void]
      def nudge = live { Live::News.publish(store: @store, keys: @keys, kind: "app") }

      # @return [Boolean]
      def restart(name, why:)
        @say.call("restarting #{name}: #{why}")
        @supervisor.restart(name)
      end

      # Apply the toolbar's requests for this plan that arrived after +cursor+.
      #
      # @param cursor [String] a stream id
      # @return [String] the last id read
      def commands(cursor)
        entries = live { @store.xread(@keys.app_commands, id: cursor) } || []
        entries.each do |entry|
          cursor = entry.id
          command = Listing.parse(entry.fields["json"])
          apply(command) if command && command["plan"] == @plan
        end
        cursor
      end

      # @param command [Hash] `plan`, `action`, `target`
      # @return [void]
      def apply(command)
        case command["action"]
        when "stop"
          @say.call("stopping: asked from the page")
          @stopping.make_true
        when "restart"
          targets(command["target"]).each { restart(it.name, why: "asked from the page") }
        end
      end

      # `backend` is every process but the previewed one, in declared order
      # (spec open question 9); a name is that process; nothing is all of them.
      #
      # @return [Array<OpenLanes::Apps::ProcessSpec>]
      def targets(target)
        case target
        when nil, "" then @definition.processes
        when "backend" then @definition.backend
        else Array(@definition.process(target))
        end
      end

      # Commands written before this runner started are not for it.
      #
      # @return [String]
      def newest_command = live { @store.xrevrange(@keys.app_commands, count: 1).first&.id } || "0-0"

      # Run a Redis call when there is a store, and survive one that went
      # away: the app matters more than the board.
      #
      # @return [Object, nil]
      def live
        return nil unless @store

        yield
      rescue Live::Unavailable => e
        @say.call("Redis: #{e.message}") unless @said_unavailable
        @said_unavailable = true
        nil
      end
    end
  end
end

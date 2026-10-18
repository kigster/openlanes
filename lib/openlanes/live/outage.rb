# frozen_string_literal: true

module OpenLanes
  module Live
    # What the engine does when its Redis stops answering (W32).
    #
    # A blip is not an outage: Redis that is back within {GRACE} seconds
    # changes nothing. Past that, every running agent is paused through its
    # control file ({Execution::Control::PAUSE}), nothing new starts, and the
    # outage goes into the run's state file, the record that survives Redis.
    # Redis is then asked again after 1, 1, 2, 3, 5, 8 … seconds, the
    # Fibonacci numbers, so a short outage is noticed quickly and a long one
    # is not hammered. When it answers, the agents carry on, their clocks
    # having stood still meanwhile. When it has not answered for
    # `redis_outage_hours` (an hour by default), the run shuts down the way
    # `q` does, and says why.
    #
    # Run on the dispatcher's tick, ahead of everything that needs Redis.
    class Outage
      # Seconds Redis may be unreachable before the agents are paused.
      GRACE = 10

      # Seconds between pings while Redis answers.
      PING_EVERY = 1

      # How many past outages the state file keeps.
      HISTORY = 20

      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param limit [Numeric] seconds paused before the run gives up
      # @param clock [#call] monotonic seconds
      # @param wall [#call] wall time, for the state file
      def initialize(store:, limit:, clock: -> { UI.monotonic }, wall: -> { Time.now })
        @store = store
        @limit = limit
        @clock = clock
        @wall = wall
        @state = :up
        @down_since = nil
        @last_ping = nil
      end

      # @return [Symbol] :up, :paused or :gave_up
      attr_reader :state

      # One tick.
      #
      # @param dispatcher [OpenLanes::Engine::Dispatcher] for its state file
      # @return [void]
      def call(dispatcher)
        @state_file = dispatcher.state_file
        now = @clock.call
        case @state
        when :up then watch(now)
        when :paused then probe(now)
        end
      end

      # @return [Boolean] whether agents are paused for this outage
      def paused? = @state == :paused

      # @return [Proc] {#call}, for `Dispatcher#before_tick`
      def to_proc = method(:call).to_proc

      private

      # @return [void]
      def watch(now)
        return if @last_ping && now - @last_ping < PING_EVERY

        @last_ping = now
        if answers?
          @down_since = nil
        else
          @down_since ||= now
          pause(now) if now - @down_since >= GRACE
        end
      end

      # @return [void]
      def pause(now)
        @state = :paused
        @delays = fibonacci
        @attempts = 0
        @next_probe = next_probe(now)
        @record = { "since" => (@wall.call - (now - @down_since)).iso8601, "paused_at" => @wall.call.iso8601,
                    "limit_seconds" => @limit.round, "attempts" => 0 }
        UI.log("Redis has not answered for #{GRACE}s: pausing every agent, starting nothing new, " \
               "and giving up after #{hours(@limit)}",
          level: :warn)
        Execution::Control.pause!
        save
      end

      # @return [void]
      def probe(now)
        return if now < @next_probe

        @attempts += 1
        @record["attempts"] = @attempts
        @record["last_attempt_at"] = @wall.call.iso8601
        if answers?
          resume(now)
        elsif now - @down_since >= @limit
          give_up(now)
        else
          @next_probe = next_probe(now)
          save
        end
      end

      # @return [void]
      def resume(now)
        @state = :up
        @record["resumed_at"] = @wall.call.iso8601
        @record["seconds"] = (now - @down_since).round
        UI.log("Redis answers again after #{(now - @down_since).round}s and #{@attempts} attempts: resuming every agent")
        Execution::Control.resume!
        @down_since = nil
        save(over: true)
      end

      # @return [void]
      def give_up(now)
        @state = :gave_up
        @record["gave_up_at"] = @wall.call.iso8601
        @record["seconds"] = (now - @down_since).round
        UI.log("Redis has not answered for #{hours(@limit)}: shutting the run down", level: :error)
        Execution::Control.quit!
        save(over: true)
      end

      # The next Fibonacci gap, but never past the limit: the gaps outgrow an
      # hour within twenty asks, and the last ask is the one at the limit.
      #
      # @return [Float]
      def next_probe(now) = [now + @delays.next, @down_since + @limit].min

      # @return [Boolean]
      def answers?
        @store.ping == true
      rescue Unavailable, SystemCallError
        false
      end

      # 1, 1, 2, 3, 5, 8, …
      #
      # @return [Enumerator]
      def fibonacci
        Enumerator.new do |out|
          a, b = 1, 1
          loop do
            out << a
            a, b = b, a + b
          end
        end
      end

      # The current outage, or, once it is over, into the history. Saved at
      # once: this is the record a person reads to learn why agents stood
      # still, and the run may not live to save it later.
      #
      # @param over [Boolean]
      # @return [void]
      def save(over: false)
        return unless @state_file

        @state_file.outage = over ? nil : @record
        @state_file.outages = (@state_file.outages + [@record]).last(HISTORY) if over
        @state_file.save
      rescue SystemCallError => e
        UI.log("outage not recorded: #{e.message}", level: :warn)
      end

      # @return [String]
      def hours(seconds)
        hours = seconds / 3600.0
        hours == hours.round ? "#{hours.round} hour#{"s" unless hours.round == 1}" : "#{hours.round(2)} hours"
      end
    end
  end
end

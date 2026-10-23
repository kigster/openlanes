# frozen_string_literal: true

require "json"

module OpenLanes
  module Live
    # Keeps the {RunState} past an engine restart (W6). Redis holds the live
    # copy under {Keys#run}; `.plans/openlanes-state.json` holds the one a
    # person can read without `redis-cli` and the one that survives Redis
    # being flushed. Both carry the state's `seq`.
    #
    # On the run's first tick, after the dispatcher has loaded its state
    # file, the newer copy is taken: normally Redis, the file when Redis came
    # back empty or behind. Queued models go back to the executor, which is
    # what applies them. From then on each tick writes whichever copy is
    # behind, and {Commands} writes Redis in the same `MULTI` as a command's
    # reply, so an applied command and its effect on the run state land
    # together.
    class RunRecord
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @param run_state [OpenLanes::Live::RunState]
      def initialize(store:, keys:, run_state:)
        @store = store
        @keys = keys
        @run_state = run_state
        @restored = false
        @in_redis = nil
        @in_file = nil
        @state_file = nil
        @warned = false
      end

      # @return [Proc] for {Engine::Dispatcher#before_tick}
      def to_proc = method(:call).to_proc

      # @param dispatcher [OpenLanes::Engine::Dispatcher]
      # @return [void]
      def call(dispatcher)
        restore(dispatcher) unless @restored
        flush
      end

      # Take back the newer copy, and hand its models to the executor.
      #
      # @param dispatcher [OpenLanes::Engine::Dispatcher]
      # @return [void]
      def restore(dispatcher)
        @restored = true
        @state_file = dispatcher.state_file
        redis = read_redis
        file = @state_file&.live
        newer = newest(redis, file)
        # A copy that is missing is behind, unless both are: then there is
        # nothing to keep until a person changes something.
        @in_redis = redis ? redis["seq"].to_i : (newer && -1) || 0
        @in_file = file ? file["seq"].to_i : (newer && -1) || 0
        return unless newer

        @run_state.restore(newer)
        @run_state.models.each do |key, model|
          ordinal, agent = key.split("/", 2)
          dispatcher.prefer_model(ordinal, agent, model)
        end
        restore_concurrency(dispatcher)
      end

      # A `/concurrency` set before the restart holds after it (plan 020.00).
      # One this run cannot take (a shared checkout runs one agent) is said
      # once and dropped, rather than stopping the engine from starting.
      #
      # @param dispatcher [OpenLanes::Engine::Dispatcher]
      # @return [void]
      def restore_concurrency(dispatcher)
        limit = @run_state.concurrency or return
        dispatcher.concurrency = limit
      rescue OpenLanes::Error => e
        UI.log("concurrency #{limit} from before the restart not kept: #{e.message}")
      end

      # After Redis comes back: which copy is the newer, by the same `seq`
      # rule as {#restore}. An RDB rollback leaves Redis behind or empty and
      # the file wins. The engine's own state kept going through the outage,
      # so nothing is restored from either; both marks are reset to what is
      # really there, so the next {#flush} rewrites whichever copy is behind.
      #
      # @return [Symbol, nil] `:redis` or `:file`, or nil with neither copy
      def reconcile
        @warned = false
        redis = read_redis
        file = @state_file&.live
        @in_redis = redis ? redis["seq"].to_i : -1
        @in_file = file ? file["seq"].to_i : -1
        newer = newest(redis, file) or return nil
        newer.equal?(redis) ? :redis : :file
      end

      # Bring both copies up to the state's `seq`. The file is written by the
      # dispatcher's own save at the end of the tick, and by {#close}.
      #
      # @return [void]
      def flush
        seq = @run_state.seq
        @store.multi { |tx| write(tx) } unless @in_redis == seq
        mirror
      rescue Unavailable => e
        unavailable(e)
      end

      # The Redis half, inside someone else's `MULTI`.
      #
      # @param transaction [#hset]
      # @return [void]
      def write(transaction)
        data = @run_state.to_h
        transaction.hset(@keys.run, "seq", data["seq"].to_s)
        transaction.hset(@keys.run, "json", JSON.generate(data))
        @in_redis = data["seq"]
      end

      # The run is over: the file gets the last word, saved now rather than
      # at a tick that is not coming.
      #
      # @return [void]
      def close
        flush
        @state_file&.save
      end

      private

      # The copy with the higher `seq`; Redis on a tie, being listed first.
      #
      # @param redis [Hash, nil]
      # @param file [Hash, nil]
      # @return [Hash, nil]
      def newest(redis, file) = [redis, file].compact.max_by { it["seq"].to_i }

      # @return [void]
      def mirror
        return unless @state_file && @in_file != @run_state.seq

        data = @run_state.to_h
        @state_file.live = data
        @in_file = data["seq"]
      end

      # @return [Hash, nil]
      def read_redis
        seq, json = @store.hgetall(@keys.run).values_at("seq", "json")
        return nil unless json

        JSON.parse(json).merge("seq" => seq.to_i)
      rescue JSON::ParserError
        nil
      rescue Unavailable => e
        unavailable(e)
        nil
      end

      # @param error [OpenLanes::Live::Unavailable]
      # @return [void]
      def unavailable(error)
        return if @warned

        @warned = true
        UI.log("run state not kept in Redis: #{error.message}")
      end
    end
  end
end

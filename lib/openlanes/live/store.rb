# frozen_string_literal: true

require "redis-client"

module OpenLanes
  module Live
    # Redis, narrowed to what the contract uses: strings with an expiry,
    # `SET NX EX` and compare-and-delete for claims, hashes, streams with a
    # consumer group, `SCAN` by prefix, and `MULTI`.
    #
    # Narrow on purpose. {MemoryStore} answers the same methods, and the
    # suite runs one shared set of examples against both, so every method
    # added here is a method the fake must earn too. A store that offered
    # all of Redis would let the engine come to depend on a command the
    # fake only pretends to understand.
    #
    # Every connection failure surfaces as {Unavailable}, so a caller that
    # wants to keep running without Redis rescues one class, not a gem's.
    class Store
      # One stream entry: its id and its fields.
      #
      # @!attribute [r] id
      #   @return [String] `<ms>-<seq>`
      # @!attribute [r] fields
      #   @return [Hash{String => String}] empty for an entry trimmed away
      #     while it was still pending
      Entry = Data.define(:id, :fields)

      # Deletes the key only when it still holds the value this process wrote.
      # A plain GET then DEL would delete a claim another node took in between.
      COMPARE_AND_DELETE = <<~LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) else return 0 end
      LUA

      # Extends the key only when it still holds this process's value, so a
      # renewal can never keep alive a claim that has passed to someone else.
      COMPARE_AND_EXPIRE = <<~LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("expire", KEYS[1], ARGV[2]) else return 0 end
      LUA

      # Seconds a connection attempt or a command may take before the store
      # reports Redis as unavailable. Short, because the engine asks on its
      # tick and a hung Redis must not hang the run.
      TIMEOUT = 2.0

      # The writes {#multi} accepts. Reads inside a transaction answer
      # nothing until it commits, so none are offered.
      WRITES = %i[set del expire hset hdel xadd xack].freeze

      # Records the writes of one {#multi} block, to be applied together.
      class Transaction
        def initialize
          @calls = []
        end

        # @return [Array<Array(Symbol, Array, Hash)>]
        attr_reader :calls

        WRITES.each do |name|
          define_method(name) do |*args, **kwargs|
            @calls << [name, args, kwargs]
            nil
          end
        end
      end

      # @param url [String]
      # @param timeout [Float] seconds
      def initialize(url:, timeout: TIMEOUT)
        @url = url
        @client = RedisClient.config(url:, timeout:, reconnect_attempts: 1).new_client
      end

      # @return [String]
      attr_reader :url

      # @return [Boolean] whether Redis answered
      def ping = call("PING") == "PONG"

      # @return [void]
      def close = @client.close

      # ---- strings ----------------------------------------------------------

      # @param key [String]
      # @return [String, nil]
      def get(key) = call("GET", key)

      # @param key [String]
      # @param value [String]
      # @param ex [Integer, nil] seconds to live
      # @param nx [Boolean] only when the key does not exist
      # @return [Boolean] whether the value was written
      def set(key, value, ex: nil, nx: false) = call(*set_command(key, value, ex:, nx:)) == "OK"

      # @param keys [Array<String>]
      # @return [Integer] how many were removed
      def del(*keys) = keys.empty? ? 0 : call("DEL", *keys)

      # @param key [String]
      # @param seconds [Integer]
      # @return [Boolean] whether the key exists to expire
      def expire(key, seconds) = call("EXPIRE", key, seconds) == 1

      # @param key [String]
      # @return [Integer] seconds left, -1 without an expiry, -2 when absent
      def ttl(key) = call("TTL", key)

      # @param key [String]
      # @param expected [String]
      # @return [Boolean] whether the key held +expected+ and is now gone
      def compare_and_delete(key, expected) = call("EVAL", COMPARE_AND_DELETE, 1, key, expected) == 1

      # @param key [String]
      # @param expected [String]
      # @param seconds [Integer]
      # @return [Boolean] whether the key held +expected+ and was extended
      def compare_and_expire(key, expected, seconds)
        call("EVAL", COMPARE_AND_EXPIRE, 1, key, expected, seconds) == 1
      end

      # ---- hashes -----------------------------------------------------------

      # @return [Boolean] whether the field is new
      def hset(key, field, value) = call("HSET", key, field, value) == 1

      # @return [String, nil]
      def hget(key, field) = call("HGET", key, field)

      # @return [Hash{String => String}]
      def hgetall(key) = call("HGETALL", key).to_h

      # @return [Integer] how many fields were removed
      def hdel(key, *fields) = fields.empty? ? 0 : call("HDEL", key, *fields)

      # ---- streams ----------------------------------------------------------

      # @param key [String]
      # @param fields [Hash{#to_s => #to_s}]
      # @param maxlen [Integer, nil] trimmed to about this many entries
      # @return [String] the new entry's id
      def xadd(key, fields, maxlen: nil) = call(*xadd_command(key, fields, maxlen:))

      # @return [Integer] entries in the stream
      def xlen(key) = call("XLEN", key)

      # Creates the group, and the stream with it. Asking twice is not an
      # error: every engine start asks.
      #
      # @param key [String]
      # @param group [String]
      # @param from [String] "0" to deliver what is already there, "$" for
      #   only what arrives later
      # @return [Boolean] whether the group is new
      def xgroup_create(key, group, from: "0")
        call("XGROUP", "CREATE", key, group, from, "MKSTREAM") == "OK"
      rescue RedisClient::CommandError => e
        raise unless e.message.start_with?("BUSYGROUP")

        false
      end

      # @param key [String]
      # @param group [String]
      # @param consumer [String]
      # @param id [String] ">" for entries never delivered, "0" for this
      #   consumer's delivered and unacknowledged ones
      # @param count [Integer]
      # @return [Array<Entry>]
      def xreadgroup(key, group, consumer, id: ">", count: 100)
        entries(call("XREADGROUP", "GROUP", group, consumer, "COUNT", count, "STREAMS", key, id)&.fetch(key, nil))
      end

      # @return [Integer] how many were acknowledged
      def xack(key, group, *ids) = ids.empty? ? 0 : call("XACK", key, group, *ids)

      # Entries after +id+. With +block+ it waits up to that many
      # milliseconds for one to arrive.
      #
      # @param key [String]
      # @param id [String] "$" for only what arrives from now
      # @param count [Integer]
      # @param block [Integer, nil] milliseconds
      # @return [Array<Entry>]
      def xread(key, id: "0", count: 100, block: nil)
        reply = if block
                  guarded { @client.blocking_call((block / 1000.0) + TIMEOUT, "XREAD", "BLOCK", block, "COUNT", count, "STREAMS", key, id) }
                else
                  call("XREAD", "COUNT", count, "STREAMS", key, id)
                end
        entries(reply&.fetch(key, nil))
      end

      # @return [Array<Entry>] oldest first
      def xrange(key, start: "-", stop: "+", count: 100) = entries(call("XRANGE", key, start, stop, "COUNT", count))

      # @return [Array<Entry>] newest first
      def xrevrange(key, stop: "+", start: "-", count: 100) = entries(call("XREVRANGE", key, stop, start, "COUNT", count))

      # ---- keys -------------------------------------------------------------

      # Every key starting with +prefix+, by cursor, so a large keyspace is
      # never asked for in one blocking `KEYS`.
      #
      # @param prefix [String]
      # @return [Array<String>]
      def scan(prefix)
        cursor = "0"
        found = []
        loop do
          cursor, batch = call("SCAN", cursor, "MATCH", "#{glob_escape(prefix)}*", "COUNT", 500)
          found.concat(batch)
          break if cursor == "0"
        end
        found.uniq.sort
      end

      # ---- transactions -----------------------------------------------------

      # The writes the block makes, applied atomically.
      #
      # @yieldparam tx [Transaction]
      # @return [void]
      def multi
        tx = Transaction.new
        yield tx
        return if tx.calls.empty?

        guarded { @client.multi { |t| tx.calls.each { |name, args, kwargs| t.call(*command_for(name, args, kwargs)) } } }
        nil
      end

      private

      # @return [Object] the reply
      def call(*command) = guarded { @client.call(*command) }

      # @return [Object] the block's value
      # @raise [OpenLanes::Live::Unavailable]
      def guarded
        yield
      rescue RedisClient::CommandError
        raise
      rescue RedisClient::Error => e
        raise Unavailable, "Redis at #{Live.mask(url)} is unavailable: #{e.message.sub(/\s*\(redis:.*\)\z/, "")}"
      end

      # @return [Array] the raw command for one transaction write
      def command_for(name, args, kwargs)
        case name
        when :set then set_command(*args, **kwargs)
        when :xadd then xadd_command(*args, **kwargs)
        else [name.to_s.upcase, *args]
        end
      end

      # @return [Array]
      def set_command(key, value, ex: nil, nx: false)
        ["SET", key, value, *("NX" if nx), *(["EX", ex] if ex)]
      end

      # @return [Array]
      def xadd_command(key, fields, maxlen: nil)
        ["XADD", key, *(["MAXLEN", "~", maxlen] if maxlen), "*", *fields.flat_map { |k, v| [k.to_s, v.to_s] }]
      end

      # @param raw [Array, nil] `[[id, [field, value, ...]], ...]`
      # @return [Array<Entry>]
      def entries(raw)
        Array(raw).map { |id, pairs| Entry.new(id:, fields: Array(pairs).each_slice(2).to_h) }
      end

      # @return [String] +prefix+ with glob metacharacters taken literally
      def glob_escape(prefix) = prefix.gsub(/[*?\[\]\\]/) { "\\#{it}" }
    end
  end
end

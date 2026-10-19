# frozen_string_literal: true

require "monitor"

module OpenLanes
  module Live
    # {Store}'s methods, kept in this process. The suite's Redis.
    #
    # It emulates exactly as much of Redis as the contract uses, and the
    # shared examples in `spec/openlanes/live/store_examples.rb` hold it to
    # the real thing: an expiry read off a clock the example controls,
    # compare-and-delete, a consumer group's pending list, and approximate
    # trimming done exactly (which `MAXLEN ~` permits: it promises at least
    # that many, never exactly that many).
    class MemoryStore
      # @param clock [Proc] seconds, monotonic; an example moves it to expire keys
      def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @clock = clock
        @mutex = Monitor.new
        @data = {}
        @expiry = {}
        @groups = Hash.new { |h, k| h[k] = {} }
        @last_ms = 0
        @last_seq = 0
        @subscribers = []
      end

      # @return [String] what {Live.mask} shows for it
      def url = "memory://"

      # @return [Boolean]
      def ping = true

      # @return [void]
      def close = nil

      # ---- strings ----------------------------------------------------------

      # @return [String, nil]
      def get(key) = locked { live(key) }

      # @return [Boolean] whether the value was written
      def set(key, value, ex: nil, nx: false)
        locked do
          next false if nx && !live(key).nil?

          @data[key] = value.to_s
          ex ? @expiry[key] = now + ex : @expiry.delete(key)
          true
        end
      end

      # @return [Integer] how many were removed
      def del(*keys) = locked { keys.count { |key| forget(key) } }

      # @return [Boolean] whether the key exists to expire
      def expire(key, seconds)
        locked do
          next false if live(key).nil?

          @expiry[key] = now + seconds
          true
        end
      end

      # @return [Integer] seconds left, -1 without an expiry, -2 when absent
      def ttl(key)
        locked do
          next -2 if live(key).nil?

          @expiry.key?(key) ? (@expiry[key] - now).ceil : -1
        end
      end

      # @return [Boolean]
      def compare_and_delete(key, expected)
        locked { live(key) == expected ? forget(key) : false }
      end

      # @return [Boolean]
      def compare_and_expire(key, expected, seconds)
        locked { live(key) == expected ? expire(key, seconds) : false }
      end

      # ---- hashes -----------------------------------------------------------

      # @return [Boolean] whether the field is new
      def hset(key, field, value)
        locked do
          hash = live(key) || (@data[key] = {})
          fresh = !hash.key?(field.to_s)
          hash[field.to_s] = value.to_s
          fresh
        end
      end

      # @return [String, nil]
      def hget(key, field) = locked { live(key)&.fetch(field.to_s, nil) }

      # @return [Hash{String => String}]
      def hgetall(key) = locked { (live(key) || {}).dup }

      # @return [Integer]
      def hdel(key, *fields)
        locked do
          hash = live(key) or next 0
          removed = fields.count { |f| hash.delete(f.to_s) }
          forget(key) if hash.empty?
          removed
        end
      end

      # ---- streams ----------------------------------------------------------

      # @return [String] the new entry's id
      def xadd(key, fields, maxlen: nil)
        locked do
          stream = live(key) || (@data[key] = [])
          id = next_id
          stream << Store::Entry.new(id:, fields: fields.to_h { |k, v| [k.to_s, v.to_s] })
          stream.shift(stream.size - maxlen) if maxlen && stream.size > maxlen
          id
        end
      end

      # @return [Integer]
      def xlen(key) = locked { (live(key) || []).size }

      # @return [Integer] how many were removed
      def xtrim(key, minid:)
        locked do
          stream = live(key) or next 0
          floor = id_of(minid.include?("-") ? minid : "#{minid}-0")
          before = stream.size
          stream.reject! { (id_of(it.id) <=> floor).negative? }
          before - stream.size
        end
      end

      # @return [Boolean] whether the group is new
      def xgroup_create(key, group, from: "0")
        locked do
          stream = live(key) || (@data[key] = [])
          next false if @groups[key].key?(group)

          last = from == "$" ? stream.last&.id || "0-0" : from
          @groups[key][group] = { last: id_of(last.include?("-") ? last : "#{last}-0"), pending: {} }
          true
        end
      end

      # @return [Array<Store::Entry>]
      def xreadgroup(key, group, consumer, id: ">", count: 100)
        locked do
          state = @groups[key][group] or raise GroupMissing, "NOGROUP #{group} on #{key}"
          stream = live(key) || []
          if id == ">"
            fresh = stream.select { |e| (id_of(e.id) <=> state[:last]).positive? }.first(count)
            fresh.each { |e| state[:pending][e.id] = consumer }
            state[:last] = id_of(fresh.last.id) unless fresh.empty?
            fresh
          else
            floor = id_of(id.include?("-") ? id : "#{id}-0")
            state[:pending].select { |pid, who| who == consumer && (id_of(pid) <=> floor).positive? }.keys
                           .sort_by { id_of(it) }.first(count)
                           .map { |pid| stream.find { |e| e.id == pid } || Store::Entry.new(id: pid, fields: {}) }
          end
        end
      end

      # @return [Integer]
      def xack(key, group, *ids)
        locked do
          pending = @groups.dig(key, group, :pending) or next 0
          ids.count { |id| pending.delete(id) }
        end
      end

      # Never waits: nothing else can add to this process's streams while
      # the caller is blocked, so +block+ is accepted and ignored.
      #
      # @return [Array<Store::Entry>]
      def xread(key, id: "0", count: 100, block: nil) # rubocop:disable Lint/UnusedMethodArgument
        locked do
          stream = live(key) || []
          next [] if id == "$"

          floor = id_of(id.include?("-") ? id : "#{id}-0")
          stream.select { |e| (id_of(e.id) <=> floor).positive? }.first(count)
        end
      end

      # @return [Array<Store::Entry>] oldest first
      def xrange(key, start: "-", stop: "+", count: 100)
        locked { within(live(key) || [], start, stop).first(count) }
      end

      # @return [Array<Store::Entry>] newest first
      def xrevrange(key, stop: "+", start: "-", count: 100)
        locked { within(live(key) || [], start, stop).reverse.first(count) }
      end

      # ---- keys -------------------------------------------------------------

      # @return [Array<String>]
      def scan(prefix) = locked { @data.keys.select { |k| k.start_with?(prefix) && !live(k).nil? }.sort }

      # ---- pub/sub ----------------------------------------------------------

      # @return [Integer] how many subscriptions received it
      def publish(channel, message)
        receivers = locked { @subscribers.dup }
        receivers.sum do |subscriber|
          subscriber.deliver(channel, message.to_s)
          subscriber.matches(channel)
        end
      end

      # @return [OpenLanes::Live::MemorySubscriber]
      def subscriber(channels: [], patterns: [])
        MemorySubscriber.new(store: self, channels:, patterns:).tap { |s| locked { @subscribers << s } }
      end

      # @param subscriber [OpenLanes::Live::MemorySubscriber]
      # @return [void]
      def unsubscribe(subscriber) = locked { @subscribers.delete(subscriber) }

      # @return [Integer] always 0: one process, one keyspace
      def db = 0

      # ---- transactions -----------------------------------------------------

      # @yieldparam tx [Store::Transaction]
      # @return [void]
      def multi
        tx = Store::Transaction.new
        yield tx
        locked { tx.calls.each { |name, args, kwargs| public_send(name, *args, **kwargs) } }
        nil
      end

      private

      # @return [Object] the block's value, under the lock
      def locked(&) = @mutex.synchronize(&)

      # @return [Float]
      def now = @clock.call

      # @return [Object, nil] the value, unless it has expired
      def live(key)
        if @expiry.key?(key) && @expiry[key] <= now
          forget(key)
          return nil
        end
        @data[key]
      end

      # @return [Boolean] whether there was anything to forget
      def forget(key)
        @expiry.delete(key)
        @groups.delete(key)
        !@data.delete(key).nil?
      end

      # Ids as Redis makes them: milliseconds, then a sequence within the
      # millisecond, always increasing even if the clock does not.
      #
      # @return [String]
      def next_id
        ms = (Time.now.to_f * 1000).to_i
        if ms > @last_ms
          @last_ms = ms
          @last_seq = 0
        else
          @last_seq += 1
        end
        "#{@last_ms}-#{@last_seq}"
      end

      # @return [Array(Integer, Integer)]
      def id_of(id) = id.split("-", 2).map(&:to_i)

      # @return [Array<Store::Entry>]
      def within(stream, start, stop)
        low = if start == "-"
                [0, 0]
              else
                id_of(start.include?("-") ? start : "#{start}-0")
              end
        high = if stop == "+"
                 [Float::INFINITY, Float::INFINITY]
               else
                 id_of(stop.include?("-") ? stop : "#{stop}-#{2**63}")
               end
        stream.select { (low..high).cover?(id_of(it.id)) }
      end
    end
  end
end

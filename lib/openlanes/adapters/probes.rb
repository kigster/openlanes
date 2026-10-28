# frozen_string_literal: true

require "json"

module OpenLanes
  module Adapters
    # The probe thread every booted process runs (plan 040, D7): at boot and
    # every {INTERVAL}, whoever wins {LOCK} probes every adapter and writes
    # the answers to one Redis key; the others read that key.
    #
    # Redis unreachable is its outage mode, not an error: the process probes
    # for itself and keeps the answers in memory until Redis is back.
    #
    #   probes = Adapters::Probes.new(store:, keys:, owner: node.name).start
    #   probes.current # => [Availability, …]
    #   probes.stop
    class Probes
      # Seconds between probes (Q3): signing in or out of a CLI shows within this.
      INTERVAL = 15 * 60

      # Seconds the key outlives its write, past {INTERVAL} so a probe that
      # runs late does not leave the page with nothing.
      EXPIRY = 20 * 60

      # Seconds the lock is held. Never released: it only has to outlast the
      # other processes' boot-time probes, and it expires long before the next.
      LOCK = 60

      # Seconds {#stop} waits for a probe round to finish before ending it.
      STOP_WAIT = 1

      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys] whose {Live::Keys#adapters} and
      #   {Live::Keys#adapters_lock} this machine's probes share
      # @param owner [String] what the lock holds, for whoever reads it
      # @param prober [#call] one round of probes, returning
      #   [Array<OpenLanes::Adapters::Availability>]; a spec hands in its own
      def initialize(store:, keys:, owner:, prober: -> { Adapters.availability })
        @store = store
        @key = keys.adapters
        @lock = keys.adapters_lock
        @owner = owner
        @prober = prober
        @memory = []
        @mutex = Mutex.new
        @wake = Thread::Queue.new
        @thread = nil
      end

      # Probes now and every {INTERVAL} after, on a thread of its own, so
      # boot never waits on a CLI.
      #
      # @return [self]
      def start
        @thread ||= Thread.new do
          loop do
            refresh
            break if @wake.pop(timeout: INTERVAL)
          end
        end
        self
      end

      # Ends the thread. A probe still waiting on its CLI is not waited for:
      # shutdown must not take a probe's timeout.
      #
      # @return [void]
      def stop
        @wake << :stop
        @thread&.join(STOP_WAIT) || @thread&.kill
      end

      # One round: probe and write the key when this process wins the lock.
      # A loser leaves the key to the winner.
      #
      # @return [Array<OpenLanes::Adapters::Availability>, nil] what was
      #   probed; nil when another process holds the lock
      def refresh
        return unless store.set(lock, owner, ex: LOCK, nx: true)

        probe_all.tap { store.set(key, JSON.generate(it.map(&:wire)), ex: EXPIRY) }
      rescue Live::Unavailable
        probe_all.tap { remember(it) }
      rescue StandardError => e
        Log.logger.warn("adapter probe failed", error: e.message)
        nil
      end

      # What the page and `openlanes agents` read: the key, else what this
      # process probed for itself during an outage, else nothing yet.
      #
      # @return [Array<OpenLanes::Adapters::Availability>]
      def current
        stored = store.get(key)
        stored ? JSON.parse(stored).map { Availability.from_wire(it) } : memory
      rescue Live::Unavailable, JSON::ParserError, KeyError
        memory
      end

      # @return [Array<OpenLanes::Adapters::Availability>]
      def probe_all = prober.call

      private

      # @return [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      attr_reader :store

      # @return [String]
      attr_reader :key

      # @return [String]
      attr_reader :lock

      # @return [String]
      attr_reader :owner

      # @return [#call]
      attr_reader :prober

      # @return [Array<OpenLanes::Adapters::Availability>]
      def memory = @mutex.synchronize { @memory }

      # @param availabilities [Array<OpenLanes::Adapters::Availability>]
      # @return [void]
      def remember(availabilities) = @mutex.synchronize { @memory = availabilities }
    end
  end
end

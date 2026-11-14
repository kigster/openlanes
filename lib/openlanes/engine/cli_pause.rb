# frozen_string_literal: true

module OpenLanes
  module Engine
    # The CLIs the engine has stopped starting agents on, because one failed
    # to authenticate (plan 065.00). Every agent started on a logged-out
    # `claude` fails the same way in two seconds, so the engine holds the
    # whole CLI, probes it with backoff, and lets it go once a probe passes.
    # Other CLIs carry on.
    class CliPause
      # One paused CLI.
      #
      # @!attribute [r] adapter
      #   @return [String]
      # @!attribute [r] reason
      #   @return [String] the CLI's own words
      # @!attribute [r] since
      #   @return [Time]
      # @!attribute [r] probe_at
      #   @return [Time] when the next probe may run
      # @!attribute [r] tries
      #   @return [Integer] probes that failed so far
      Entry = Data.define(:adapter, :reason, :since, :probe_at, :tries) do
        # @return [Hash] as the live snapshot sends it
        def to_h = { adapter:, reason:, since: since.iso8601 }
      end

      # Seconds to the first probe, doubled after each failed one up to {CEILING}.
      FIRST = 30
      # @return [Integer]
      CEILING = 600

      # @param prober [#call] `prober.call(adapter)` returns true when the CLI
      #   is signed in again; defaults to the adapter's own probe
      # @param clock [#call] returns the current Time
      def initialize(prober: ->(name) { Adapters.availability(names: [name]).first&.available }, clock: -> { Time.now })
        @prober = prober
        @clock = clock
        @entries = {}
        # Probes that failed, kept past a release: `claude auth status` can
        # say signed in while the stored token has already expired, so a CLI
        # released and paused again waits longer each time, not 30 s again.
        @strikes = Hash.new(0)
        @mutex = Mutex.new
      end

      # @param adapter [#to_s]
      # @param reason [String]
      # @return [void]
      def pause(adapter, reason)
        now = @clock.call
        @mutex.synchronize do
          tries = @strikes[adapter.to_s]
          @entries[adapter.to_s] ||= Entry.new(adapter: adapter.to_s, reason: reason.to_s, since: now, probe_at: now + wait(tries), tries:)
        end
      end

      # Forget the failed probes of a CLI an agent has just spent something
      # on: it is signed in for real, so its next pause starts at {FIRST}.
      #
      # @param adapter [#to_s]
      # @return [void]
      def clear(adapter) = @mutex.synchronize { @strikes.delete(adapter.to_s) }

      # @param adapter [#to_s]
      # @return [Boolean]
      def paused?(adapter) = @mutex.synchronize { @entries.key?(adapter.to_s) }

      # @return [Array<Entry>] oldest first
      def entries = @mutex.synchronize { @entries.values.sort_by(&:since) }

      # Probe every paused CLI whose backoff has run out, and let go of each
      # one that answers.
      #
      # @return [Array<String>] the CLIs released
      def probe
        now = @clock.call
        entries.select { it.probe_at <= now }.filter_map do |entry|
          next entry.adapter if release?(entry)

          @mutex.synchronize { @entries[entry.adapter] = entry.with(probe_at: now + wait(entry.tries + 1), tries: entry.tries + 1) }
          nil
        end
      end

      # @return [String, nil] the idle line's clause, nil when nothing is paused
      def reason
        list = entries
        return nil if list.empty?

        list.map { "#{it.adapter} paused: #{it.reason}; waiting for #{it.adapter} auth status" }.join("; ")
      end

      private

      # @return [Integer] seconds to wait after +tries+ failed probes
      def wait(tries) = [FIRST * (2**tries), CEILING].min

      def release?(entry)
        return false unless @prober.call(entry.adapter)

        @mutex.synchronize do
          @entries.delete(entry.adapter)
          @strikes[entry.adapter] = entry.tries + 1
        end
        true
      end
    end
  end
end

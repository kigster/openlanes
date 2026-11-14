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
        @mutex = Mutex.new
      end

      # @param adapter [#to_s]
      # @param reason [String]
      # @return [void]
      def pause(adapter, reason)
        now = @clock.call
        @mutex.synchronize do
          @entries[adapter.to_s] ||= Entry.new(adapter: adapter.to_s, reason: reason.to_s, since: now, probe_at: now + FIRST, tries: 0)
        end
      end

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

          wait = [FIRST * (2**(entry.tries + 1)), CEILING].min
          @mutex.synchronize { @entries[entry.adapter] = entry.with(probe_at: now + wait, tries: entry.tries + 1) }
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

      def release?(entry)
        return false unless @prober.call(entry.adapter)

        @mutex.synchronize { @entries.delete(entry.adapter) }
        true
      end
    end
  end
end

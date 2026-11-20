# frozen_string_literal: true

module OpenLanes
  module Execution
    module Throttle
      # The adapters no new agent starts on, because an agent on one is
      # waiting out its provider's rate limit or overload (C13). Before this,
      # one agent sat in a 30 s wait while the dispatcher started six more on
      # the same `claude` into the same limit, each of which then waited too.
      #
      # One per run, shared by the executor that sets it (every agent of a
      # worktree run is a thread of the one process) and the dispatcher that
      # reads it, and by the live page that shows it. Agents already running
      # carry on; other adapters are unaffected. A pause ends by the clock
      # alone, when the wait that set it would have, so nothing has to
      # remember to lift it.
      class AdapterPause
        # One paused adapter.
        #
        # @!attribute [r] adapter
        #   @return [String]
        # @!attribute [r] cause
        #   @return [String] "rate limit" or "provider overload"
        # @!attribute [r] since
        #   @return [Time] when the first wait of this pause began
        # @!attribute [r] ends_at
        #   @return [Time] when the longest wait still running ends
        Entry = Data.define(:adapter, :cause, :since, :ends_at) do
          # @return [Hash] as the live snapshot sends it, beside the CLIs
          #   paused for a failed login
          def to_h = { adapter:, reason: "paused for #{cause}", since: since.iso8601, until: ends_at.iso8601 }

          # @return [String] "claude paused for rate limit until 09:42"
          def to_s = "#{adapter} paused for #{cause} until #{ends_at.strftime("%H:%M")}"
        end

        # @param clock [#call] returns the current Time
        def initialize(clock: -> { Time.now })
          @clock = clock
          @entries = {}
          @mutex = Mutex.new
        end

        # Pause +adapter+ for +seconds+ from now, or longer if a wait already
        # holds it past that: a second agent's shorter wait must not cut the
        # first one's pause short.
        #
        # @param adapter [#to_s]
        # @param seconds [Numeric]
        # @param cause [String]
        # @return [Entry]
        def hold(adapter, seconds, cause: "rate limit")
          now = @clock.call
          name = adapter.to_s
          @mutex.synchronize do
            held = live(name, now) || Entry.new(adapter: name, cause:, since: now, ends_at: now)
            @entries[name] = held.with(cause:, ends_at: [held.ends_at, now + seconds].max)
          end
        end

        # @param adapter [#to_s]
        # @return [Boolean]
        def paused?(adapter) = !self[adapter].nil?

        # @param adapter [#to_s]
        # @return [Entry, nil] the adapter's pause, nil once it has run out
        def [](adapter)
          now = @clock.call
          @mutex.synchronize { live(adapter.to_s, now) }
        end

        # @return [Array<Entry>] every pause still running, oldest first
        def entries
          now = @clock.call
          @mutex.synchronize do
            @entries.delete_if { |_, entry| entry.ends_at <= now }
            @entries.values.sort_by(&:since)
          end
        end

        # @return [String, nil] the idle line's clause, nil when nothing is paused
        def reason
          list = entries
          list.join("; ") unless list.empty?
        end

        private

        # @return [Entry, nil] called under the mutex
        def live(name, now)
          entry = @entries[name] or return nil
          return entry if entry.ends_at > now

          @entries.delete(name)
          nil
        end
      end
    end
  end
end

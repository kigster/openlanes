# frozen_string_literal: true

module OpenLanes
  module Engine
    module Steps
      # At most one {Vcs::GitHub#open_pull_snapshot} per interval, handed to
      # every reader that asks within it. Readers in one tick therefore see
      # the same pull requests, and GitHub is asked once rather than once per
      # reader per pull request.
      class Snapshot
        # @param github [#open_pull_snapshot]
        # @param seconds [Numeric] how long one snapshot is good for
        # @param clock [#call] monotonic seconds
        def initialize(github:, seconds: POLL, clock: -> { ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) })
          @github = github
          @seconds = seconds
          @clock = clock
          @taken = nil
          @current = nil
          @lock = Mutex.new
        end

        # @return [Vcs::PullSnapshot] the current snapshot, taken now when the
        #   last one is older than the interval
        # @raise [OpenLanes::Error] when GitHub cannot be read
        def call
          @lock.synchronize do
            now = @clock.call
            unless @current && now - @taken < @seconds
              @current = @github.open_pull_snapshot
              @taken = now
            end
            @current
          end
        end

        # Drops the current snapshot, so the next {#call} takes a fresh one.
        #
        # @return [void]
        def refresh!
          @lock.synchronize { @current = nil }
        end
      end
    end
  end
end

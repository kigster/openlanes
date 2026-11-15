# frozen_string_literal: true

module OpenLanes
  module Engine
    class Arbitration
      # How often one question to the arbitrator came back unreadable, and
      # whether it may be asked again yet: after {BACKOFF} seconds, doubled
      # each time, and never once {ATTEMPTS} answers could not be read.
      #
      # One count for every question the engine puts to the arbitrator, the
      # rulings and the time requests ({Overtime}) alike, so "unreadable,
      # backed off, given up on" means one thing wherever it is said.
      # Kept in memory: a restarted engine asks afresh, which costs one
      # more answer and never a wrong ruling.
      class Retries
        # @param clock [#call] the time now
        def initialize(clock:)
          @clock = clock
          @failures = {}
        end

        # @param key [Array] the plan and what was asked about it
        # @return [Integer] how many answers to it could not be read, this one included
        def failed!(key)
          failure = @failures[key] = { count: count(key) + 1, at: @clock.call }
          failure[:count]
        end

        # @param key [Array]
        # @return [void] an answer was read: the count starts again
        def clear(key) = @failures.delete(key)

        # @param key [Array]
        # @return [Integer]
        def count(key) = @failures.dig(key, :count) || 0

        # @param key [Array]
        # @return [Boolean] whether the engine has stopped asking
        def given_up?(key) = count(key) >= ATTEMPTS

        # @param key [Array]
        # @return [Boolean] whether it is given up on, or still waiting out its back-off
        def backing_off?(key)
          failure = @failures[key] or return false
          return true if given_up?(key)

          @clock.call - failure[:at] < BACKOFF * (2**(failure[:count] - 1))
        end
      end
    end
  end
end

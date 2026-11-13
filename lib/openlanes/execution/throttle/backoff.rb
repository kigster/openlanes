# frozen_string_literal: true

module OpenLanes
  module Execution
    module Throttle
      # How long a throttled agent waits, and when it stops waiting.
      #
      # Each wait doubles from {INITIAL} up to {CAP}, plus up to a quarter
      # again of jitter, so seven agents limited in the same second do not all
      # come back in the same second and trip the limit together. A provider
      # that names its own wait (`retry-after`) is believed over the schedule.
      #
      # Two ceilings end it, {ATTEMPTS} and {BUDGET}, because an account that
      # is out of quota until midnight would otherwise hold a slot all night
      # and say nothing. Past either, {Waits#surrender} words a failure that
      # names the limit, so it does not read as the agent's own.
      #
      # The policy holds no state; {#waits} hands out the count for one
      # invocation.
      class Backoff
        # Seconds before the first retry. The CLIs retry a 429 themselves for
        # a while before reporting it, so a short first wait would only repeat
        # what just failed.
        INITIAL = 30

        # The longest single wait, in seconds.
        CAP = 600

        # How many times one invocation is started again.
        ATTEMPTS = 8

        # Seconds one invocation may spend waiting, all waits together.
        BUDGET = 3600

        # Of each wait, how much more jitter may add.
        JITTER = 0.25

        # Seconds between looks at whether somebody stopped the agent
        # meanwhile.
        SLICE = 1

        # The ceilings and the schedule, each replaceable by name.
        LIMITS = { initial: INITIAL, cap: CAP, attempts: ATTEMPTS, budget: BUDGET }.freeze

        # @return [Numeric]
        attr_reader :initial, :cap, :attempts, :budget

        # @param random [#rand] the jitter's source; a spec hands in a fixed one
        # @param sleep [#call] seconds → waits that long; a spec hands in one
        #   that returns at once
        # @param limits [Hash{Symbol => Numeric}] any of {LIMITS}: `initial`
        #   seconds before the first retry, `cap` on a single wait, `attempts`
        #   per invocation, `budget` seconds of waiting per invocation
        # @raise [ArgumentError] on a limit {LIMITS} does not name
        def initialize(random: Random.new, sleep: ->(seconds) { Kernel.sleep(seconds) }, **limits)
          unknown = limits.keys - LIMITS.keys
          raise ArgumentError, "unknown backoff limit: #{unknown.join(", ")}" unless unknown.empty?

          @initial, @cap, @attempts, @budget = LIMITS.merge(limits).values_at(:initial, :cap, :attempts, :budget)
          @random = random
          @sleep = sleep
        end

        # @return [OpenLanes::Execution::Throttle::Backoff::Waits] the count
        #   for one invocation
        def waits = Waits.new(self)

        # @param attempt [Integer] 1 for the first retry
        # @param limit [OpenLanes::Execution::Throttle::Limit]
        # @return [Float] seconds to wait before that retry
        def delay(attempt, limit)
          base = limit.retry_after || [initial * (2**(attempt - 1)), cap].min
          base + (base * JITTER * @random.rand)
        end

        # Wait +seconds+, a {SLICE} at a time, giving up the moment the block
        # says the agent was stopped: a person who pressed stop on a waiting
        # agent must not be answered ten minutes later.
        #
        # @param seconds [Numeric]
        # @yieldreturn [Boolean] whether to stop waiting
        # @return [Boolean] true when the whole wait passed, false when cut short
        def pause(seconds)
          left = seconds
          while left.positive?
            return false if yield

            step = [left, SLICE].min
            @sleep.call(step)
            left -= step
          end
          !yield
        end

        # One invocation's retries so far.
        class Waits
          # @return [Integer] retries granted so far
          attr_reader :count

          # @return [Float] seconds of waiting granted so far
          attr_reader :waited

          # @param backoff [OpenLanes::Execution::Throttle::Backoff]
          def initialize(backoff)
            @backoff = backoff
            @count = 0
            @waited = 0.0
          end

          # @param limit [OpenLanes::Execution::Throttle::Limit]
          # @return [Float, nil] seconds to wait before starting again; nil
          #   when the retries or the budget are spent, or the provider asked
          #   for longer than what is left of it
          def next(limit)
            return nil if count >= @backoff.attempts

            seconds = @backoff.delay(count + 1, limit)
            return nil if waited + seconds > @backoff.budget

            @count += 1
            @waited += seconds
            seconds
          end

          # @param limit [OpenLanes::Execution::Throttle::Limit]
          # @return [String] why the invocation is given up on, naming the
          #   limit rather than the agent
          def surrender(limit)
            asked = limit.retry_after ? ", and the provider asks for #{limit.retry_after.round}s more" : ""
            "#{limit}: gave up after #{count} #{count == 1 ? "retry" : "retries"} " \
              "and #{waited.round}s of waiting#{asked} (#{limit.detail})"
          end
        end
      end
    end
  end
end

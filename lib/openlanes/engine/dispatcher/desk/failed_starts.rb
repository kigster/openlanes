# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # The hold on an agent whose starts keep failing before it spends
        # anything (plan 065.00), read from the plan's `state.json` so a
        # restart lifts nothing a person did not.
        class FailedStarts
          # How many failed starts in a row stop an agent on a visit. Each one
          # cost nothing, so without a cap a CLI that fails in two seconds
          # would be started again on every tick.
          CAP = 3

          # Seconds before an agent whose last start failed is tried again,
          # doubled for each failed start in the run: a network blip of ten
          # seconds once spent all three tries inside eight.
          BACKOFF = 30

          # @param ledger [RoundLedger]
          # @param extensions [OpenLanes::Engine::Extensions]
          # @param clock [#now]
          def initialize(ledger:, extensions:, clock:)
            @ledger = ledger
            @extensions = extensions
            @clock = clock
          end

          # Why an agent is not started on a plan, when its starts keep
          # failing: `:capped` once {CAP} in a row failed, until a person
          # grants it a round; `:backing_off` while it waits for its next try.
          # A failed login is not counted, since {CliPause} holds the whole
          # CLI for it, and a grant settled after the run of failures starts
          # the count again.
          #
          # @param subject [OpenLanes::Plans::Subject]
          # @param agent [OpenLanes::Agents::Agent]
          # @return [Symbol, nil] nil when it may start
          def hold(subject, agent)
            count, last = streak(subject, agent)
            return nil if count.to_i.zero?
            return :capped if count >= CAP

            :backing_off if last && @clock.now < last + (BACKOFF * (2**(count - 1)))
          end

          # @param subject [OpenLanes::Plans::Subject]
          # @param agent [OpenLanes::Agents::Agent]
          # @return [Array(Integer, Time), nil] failed starts in a row that
          #   count, and when the latest ended; nil when there is no ledger
          def streak(subject, agent)
            rounds, moves = @ledger.ledger_for(subject)
            return nil unless rounds

            name = agent.name
            state = subject.status.key
            count = Plans::Rounds::Count.new(since: @extensions.lifted_at(subject.feature.path, name, state),
              except: Execution::Executor::AUTH_FAILURE)
            [rounds.failed_starts(name, state, moves:, count:), rounds.last_failed_start(name, state, moves:, count:)]
          end
        end
      end
    end
  end
end

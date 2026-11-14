# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # The run's mutable collections, mutated in place and never replaced,
        # so every step sees the same list the loop does.
        #
        # - `running` the jobs running now; `recent` settled rows still on
        #   the screen, `{ at:, row: }`; `attempts` every {Runner::Attempt}
        # - `history` each agent's rounds on each plan, by `[ordinal, agent]`,
        #   guarded by `mutex`, as is `asked_how_to_test`
        # - `finished_plans` plans with nothing left for this run to do
        # - `preferred_agents` the agent a `next:` named, by ordinal
        # - `invocations` when each running job was invoked, by key
        # - `requeues` keys of jobs a person asked to run again
        # - `discarding` {Discard}s by ordinal; `holds` pair holds not yet
        #   applied, ordinal => state (issue #172); `fenced` plans whose claim
        #   another machine took
        # - `said_outside` the outside holder last said, by ordinal
        # - `refusals` plans this pass could not claim
        # - `verifying` what each verified plan waits on; `said_verifying`
        #   the wait last logged, by ordinal
        Registers = Data.define(:running,
          :recent,
          :attempts,
          :history,
          :finished_plans,
          :asked_how_to_test,
          :preferred_agents,
          :invocations,
          :mutex,
          :requeues,
          :discarding,
          :holds,
          :fenced,
          :said_outside,
          :refusals,
          :verifying,
          :said_verifying) do
          # @return [Registers] every collection empty
          def self.fresh = new(**self::FRESH.transform_values(&:call))
        end

        # How each register starts: a fresh object per desk, never shared.
        Registers::FRESH = {
          running: -> { [] }, recent: -> { [] }, attempts: -> { [] },
          history: -> { Hash.new { |h, k| h[k] = [] } }, finished_plans: -> { [] },
          asked_how_to_test: -> { Set.new }, preferred_agents: -> { {} }, invocations: -> { {} },
          mutex: -> { Mutex.new }, requeues: -> { [] }, discarding: -> { {} }, holds: -> { {} },
          fenced: -> { [] }, said_outside: -> { {} }, refusals: -> { Set.new }, verifying: -> { {} },
          said_verifying: -> { {} }
        }.freeze
      end
    end
  end
end

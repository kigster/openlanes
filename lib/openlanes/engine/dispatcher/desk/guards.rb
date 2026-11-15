# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # Agents outside openlanes (W31), this run's own claims, and the
        # records a stopped round leaves, and the CLIs no agent is started on
        # ({CliPause}, the runner's own so the page shares it). A dry run
        # claims nothing, asks nothing and writes no state.json, so it starts
        # no lock's clock.
        Guards = Data.define(:agent_locks, :locks, :lock_clock, :finishes, :records, :cli_pause) do
          # @param runner [OpenLanes::Engine::Runner]
          # @param clock [#now, #sleep]
          # @return [Guards]
          def self.for(runner, clock)
            dry = runner.dry_run?
            outside = dry ? nil : Engine.agent_locks(runner.tree.dir, own: runner.agents.all.map(&:name))
            new(agent_locks: outside,
              locks: PlanLocks.new(agent_locks: outside),
              lock_clock: dry ? nil : Plans::LockClock.new,
              finishes: Finishes.new(runner:, clock:),
              records: Recovery::Records.new(dry_run: dry),
              cli_pause: runner.respond_to?(:cli_pause) ? runner.cli_pause : CliPause.new)
          end
        end
      end
    end
  end
end

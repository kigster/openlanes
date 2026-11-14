# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Assign < Step
        # The next agent and plan to start: plans in the order that unblocks
        # the most, and the first agent offered one that may take a round.
        class Candidates < Step
          # @param desk [Desk]
          # @param quota [Quota] whether an agent may take another round
          # @param upkeep [Upkeep] puts the tree right first
          # @param gate [QualityGate] holds everything until quality is set
          def initialize(desk, quota:, upkeep:, gate:)
            super(desk)
            @quota = quota
            @upkeep = upkeep
            @gate = gate
            @refusals = Refusals.new(desk)
          end

          # Honours a `next:` an agent wrote over definition order.
          #
          # @return [Array(OpenLanes::Agents::Agent, OpenLanes::Plans::Subject), nil]
          def next_dispatchable
            @upkeep.reconcile
            # A 💣 stops new work, not work under way; with Redis lost (W32)
            # nobody new starts, since no claim could be checked.
            return nil if runner.halted? || Execution::Control.paused? || @gate.awaited?

            @refusals.prepare
            blockers_first(runner.in_scope).lazy.filter_map { pick(it) }.first
          end

          # Plans that others wait for go first, so the work that unblocks the
          # most is started soonest. Stable: plans nobody waits for keep the
          # tree's order among themselves, and so do the blockers.
          #
          # @param subjects [Array<OpenLanes::Plans::Subject>]
          # @return [Array<OpenLanes::Plans::Subject>]
          def blockers_first(subjects)
            deps = @refusals.dependencies || runner.dependencies
            subjects.each_with_index.sort_by { |s, i| [deps.blocks_of(s.feature.ordinal).empty? ? 1 : 0, i] }.map(&:first)
          end

          private

          # A plan an agent is in right now is judged by its folder's name, and
          # never reconciled; any other by what its contents justify.
          def pick(subject)
            working = working_on(subject)
            state = working.empty? ? runner.effective_status(subject) : subject.status
            return nil if out_of_play?(subject, state) || @refusals.refused?(subject)

            agent = offered(subject, state, working).find { may_take?(it, subject) }
            agent && [agent, subject]
          end

          def working_on(subject) = running.select { plan_of(it) == ordinal_of(subject) }.map { it.task.agent }

          # A later review pass waits for the earlier one and for CI ({Reviews#due?}).
          def may_take?(agent, subject) = @quota.eligible?(agent, subject) && runner.reviews.due?(subject, agent)

          # Settled, stopped, finished in this run, verified and waiting on CI
          # (the engine's to settle), or ruled on by deploy-assessor (the
          # merges are the engine's).
          def out_of_play?(subject, state)
            Plans::StateMachine::SETTLED.include?(state.key) || runner.stopped?(state) ||
              finished_plans.include?(ordinal_of(subject)) || runner.verification&.awaiting_ci?(subject) ||
              runner.merging&.assessed?(subject) || false
          end

          def offered(subject, state, working)
            candidates = partners_only(Agents::Routing.offer(runner.agents, state, subject), working, state)
            preferred = preferred_agents[ordinal_of(subject)]
            if preferred
              candidates.sort_by { |a| a.name == preferred ? 0 : 1 }
            else
              candidates
            end
          end

          # One agent at a time on a plan, except a pair working the same
          # state. Judging a busy plan by its contents is how a chain once ran
          # inside ⚪ New with every agent's Completed held by a partner.
          def partners_only(candidates, working, state)
            return candidates if working.empty?

            team = runner.agents.team_for(state).map(&:name)
            return [] unless working.all? { team.include?(it.name) }

            candidates.select { team.include?(it.name) }
          end

          def ordinal_of(subject) = subject.feature.ordinal.to_s
        end
      end
    end
  end
end

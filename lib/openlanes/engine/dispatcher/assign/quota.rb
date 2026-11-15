# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Assign < Step
        # How many rounds an agent has had on a plan's state, whether it may
        # have another, and the request for more once it has used them all.
        class Quota < Step
          # @param desk [Desk]
          # @param stalls [Stalls] asks for an agent parked by failed starts
          def initialize(desk, stalls: Stalls.new(desk))
            super(desk)
            @stalls = stalls
          end

          # @param agent [OpenLanes::Agents::Agent]
          # @param subject [OpenLanes::Plans::Subject]
          # @return [Boolean]
          def eligible?(agent, subject)
            ordinal = subject.feature.ordinal.to_s
            # A capped plan is the arbitrator's; one it is being asked about
            # waits for the ruling, which may move it.
            return false if runner.arbitration&.holds?(subject) || arbitrating_now.include?(ordinal)
            return false if running_on?(agent, ordinal) || held?(agent, subject)

            past = past_rounds(subject, agent)
            return true if past.empty?
            return false if %w[Completed Blocked].include?(past.last[:status])

            past.size < allowance(agent, subject)
          end

          # Agents that used every round they had on a plan's state without
          # finishing ask for another. Before the dispatch, so a round granted
          # on its own starts in the same pass.
          #
          # @return [void]
          def ask_for_rounds
            return if runner.dry_run? || runner.halted?

            busy = untouchable
            # Fresh from disk: a round started on a plan renames it without
            # touching the cached tree, and an exhausted Building agent read
            # against a stale Planned would never be asked about.
            runner.tree.reload
            runner.in_scope.each { |subject| ask_on(subject) unless settled_or_busy?(subject, busy) }
          end

          private

          def ask_on(subject)
            Agents::Routing.offer(runner.agents, subject.status, subject).each do |agent|
              @stalls.ask(agent, subject)
              last = out_of_rounds(agent, subject) or next
              extensions.exhausted(subject.feature.path, agent.name, subject.status.key, last[:round])
            end
          end

          def settled_or_busy?(subject, busy)
            busy.include?(subject.feature.ordinal.to_s) || Plans::StateMachine::SETTLED.include?(subject.status.key)
          end

          # @return [Hash, nil] the agent's last round on the plan's state,
          #   when it was its last allowed one
          def out_of_rounds(agent, subject)
            past = past_rounds(subject, agent)
            return nil if past.empty? || %w[Completed Blocked].include?(past.last[:status])
            # A Started round is only still under way while its job runs. One
            # with no job was once skipped here like any other, and its agent
            # sat at its budget with nobody asked.
            return nil if past.last[:status] == "Started" && running_on?(agent, subject.feature.ordinal.to_s)
            return nil if past.size < allowance(agent, subject)

            past.last
          end

          def running_on?(agent, ordinal)
            running.any? { |j| j.task.agent.name == agent.name && j.task.subject.feature.ordinal.to_s == ordinal }
          end

          # Held by its own failed starts, or with every agent on its CLI
          # while that CLI cannot log in (plan 065.00).
          def held?(agent, subject)
            !failed_start_hold(subject, agent).nil? || cli_pause.paused?(adapter_of(agent, subject).name)
          end

          def allowance(agent, subject)
            rounds_for(agent) + extensions.rounds(subject.feature.path, agent.name, subject.status.key)
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # Each agent's rounds on a plan's current state, as `state.json` has
        # them ({Plans::Rounds}, plan 065.00). The first time this process
        # asks, the {Registers}' history is seeded from disk, so a restarted
        # engine carries on at the round the last one reached instead of
        # telling the agent round 1 again and then finding no closing ledger
        # line for the round it counted. Handbacks made later in the run
        # (resume, requeue) still edit the in-memory history.
        class RoundLedger
          # @param registers [Registers]
          # @param runner [OpenLanes::Engine::Runner]
          def initialize(registers:, runner:)
            @registers = registers
            @runner = runner
            @seeded = Set.new
            @floors = Hash.new(0)
          end

          # @param subject [OpenLanes::Plans::Subject]
          # @param agent [OpenLanes::Agents::Agent]
          # @return [Array<Hash>] `{state:, status:, round:}`, oldest first
          def past_rounds(subject, agent)
            key = [subject.feature.ordinal.to_s, agent.name]
            state = subject.status.key
            @registers.mutex.synchronize do
              entries = @registers.history[key]
              seed(entries, subject, agent) if @seeded.add?([*key, state])
              entries.select { |h| h[:state] == state }
            end
          end

          # @param subject [OpenLanes::Plans::Subject]
          # @param agent [OpenLanes::Agents::Agent]
          # @return [Integer] the round to tell the agent: one past what this
          #   process counted, and never below what `state.json` had spent or
          #   signed when this process first looked. A round handed back later
          #   in the run keeps its number, since it was never spent.
          def next_round(subject, agent)
            counted = past_rounds(subject, agent).size + 1
            [counted, @floors[[subject.feature.ordinal.to_s, agent.name, subject.status.key]]].max
          end

          # @param subject [OpenLanes::Plans::Subject]
          # @return [Array(Plans::Rounds, Integer), nil] the plan's rounds and
          #   its moves count; nil on a dry run or for a plan folder not on disk
          def ledger_for(subject)
            return nil if @runner.dry_run? || !File.directory?(subject.feature.path.to_s)

            state = Plans::PlanState.for(subject.feature.path)
            [Plans::Rounds.from(state), state.moves]
          end

          private

          def seed(entries, subject, agent)
            rounds, moves = ledger_for(subject)
            return unless rounds

            name = agent.name
            state = subject.status.key
            @floors[[subject.feature.ordinal.to_s, name, state]] = rounds.next(name, state, moves:)
            rounds.visit(name, state, moves:).each { |stage| record(entries, state, stage) }
          end

          # One entry a round: a stage this process already remembers is left as it is.
          def record(entries, state, stage)
            round = stage["round"].to_i
            return if entries.any? { |h| h[:state] == state && h[:round] == round }

            entries << { state:, status: stage["status"].to_s, round: }
          end
        end
      end
    end
  end
end

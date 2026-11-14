# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # Questions about a plan read fresh from the main tree, never from the
        # copy a step was handed, which may already have been renamed.
        class Lookups
          # @param runner [OpenLanes::Engine::Runner]
          def initialize(runner)
            @runner = runner
          end

          # @param ordinal [String]
          # @return [Boolean] whether the plan is in this run's scope now
          def in_run?(ordinal)
            subject = fresh_by(Plans::Ordinal.parse(ordinal))
            !subject.nil? && @runner.in_scope?(subject)
          end

          # @param task [OpenLanes::Engine::Runner::Task]
          # @return [OpenLanes::Plans::Ledger::Reading]
          def read_ledger(task)
            subject = fresh(task) or return Plans::Ledger::Reading.empty
            Plans::Ledger.read(subject.feature.path, task.agent.ledger)
          end

          # @param agent [OpenLanes::Agents::Agent]
          # @return [Boolean] whether this agent's run is wrapped in the plan's app
          def verifier?(agent)
            agent.phase.to_s == Verification::PHASE && !@runner.verification.nil? && !@runner.dry_run?
          end

          # @param agent [OpenLanes::Agents::Agent]
          # @return [Boolean] whether this agent's note carries merge verdicts
          def assessor?(agent) = agent.phase.to_s == Merging::PHASE && !@runner.merging.nil?

          # @return [OpenLanes::Plans::Subject, nil] the plan read fresh from the main tree
          def fresh(task) = fresh_by(task.subject.feature.ordinal)

          # @return [OpenLanes::Plans::Subject, nil]
          def fresh_by(ordinal) = Plans::Tree.new(dir: @runner.tree.dir).find(ordinal)
        end
      end
    end
  end
end

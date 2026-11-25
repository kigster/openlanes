# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Desk
        # Which CLI, model and how many rounds an agent gets on a plan, asked
        # of the executor when it can say and of the agent's own frontmatter
        # when it cannot.
        class Profiles
          # @param runner [OpenLanes::Engine::Runner]
          # @param rounds [Integer, nil] `--rounds`, in place of each agent's own
          # @param extensions [OpenLanes::Engine::Extensions]
          def initialize(runner:, rounds:, extensions:)
            @runner = runner
            @rounds = rounds
            @extensions = extensions
            @models = {}
          end

          # @return [Hash{Array => String}] model labels, by
          #   `[ordinal, agent, root]`, so spec.md is read once and not once a frame
          attr_reader :models

          # @param agent [OpenLanes::Agents::Agent]
          # @param subject [OpenLanes::Plans::Subject]
          # @return [OpenLanes::Adapters::Base]
          def adapter_of(agent, subject)
            return Agents::Profile.resolve(agent).adapter unless profiled?

            executor.profile_for(agent, subject).adapter
          end

          # A preview does nothing a second round could build on, and four
          # rounds of it listed every agent four times.
          #
          # `--rounds` replaces the agent's own number rather than capping it.
          # As a cap it could only lower it, so `--rounds 6` on a researcher
          # declaring one round still gave it one, and the plan stalled.
          #
          # @param agent [OpenLanes::Agents::Agent]
          # @return [Integer] at most {Agents::Agent::MAX_ROUNDS}
          def rounds_for(agent)
            return 1 if @runner.dry_run?

            (@rounds || agent.rounds).clamp(1, Agents::Agent::MAX_ROUNDS)
          end

          # Every round the agent may run on the plan's state: its own, plus
          # the ones a person or the harness granted (E1), which is what the
          # board shows as "Round 2 of 3".
          #
          # @param agent [OpenLanes::Agents::Agent]
          # @param subject [OpenLanes::Plans::Subject]
          # @return [Integer]
          def rounds_allowed(agent, subject)
            return rounds_for(agent) if @runner.dry_run?

            rounds_for(agent) + @extensions.rounds(subject.feature.path, agent.name, subject.status.key)
          end

          # @param agent [OpenLanes::Agents::Agent]
          # @param subject [OpenLanes::Plans::Subject, nil] whose spec.md may override it
          # @param root [String, nil] the plan's checkout, whose diff picks a `small_diff:` model
          # @return [String]
          def model_for(agent, subject = nil, root: nil)
            return unprofiled_model(agent) unless subject && profiled?

            models[[subject.feature.ordinal.to_s, agent.name, root]] ||= profile(agent, subject, root).label
          end

          # @return [Hash] adapter, model and effort, when the executor can say
          def profile_fields(agent, subject, root: nil)
            return {} unless profiled?

            found = profile(agent, subject, root)
            { adapter: found.adapter.name, model: found.model, effort: found.effort }
          end

          private

          def executor = @runner.executor

          def profiled? = executor.respond_to?(:profile_for)

          def unprofiled_model(agent) = (executor.respond_to?(:model) && executor.model) || agent.model || "default"

          # `root:` only when there is one: an executor without a checkout to
          # diff takes the two-argument form.
          def profile(agent, subject, root)
            root ? executor.profile_for(agent, subject, root:) : executor.profile_for(agent, subject)
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Agents
    # Which coding agent runs an agent on a particular plan, on which model,
    # thinking how hard: the agent's own frontmatter, overridden by what the
    # plan's author asked for, overridden by what the operator typed.
    #
    # Precedence, highest first:
    #
    #   0. a failed reviewer's replacement     (adapter only, D14 in plan 031)
    #   1. `run --model`                       (model only)
    #   2. spec.md `phases.<phase>`            (adapter, model, effort)
    #   3. `.openlanes.yml` `sizing:`          (model, effort; builders only, plan 060)
    #   4. spec.md `depth`                     (effort only)
    #   5. the agent's frontmatter
    #   6. `.openlanes.yml` `review.adapters:` (adapter only, reviewers only, plan 031)
    #   7. `.openlanes.yml` `adapter:`         (adapter only, plan 040)
    #   8. {Adapters::DEFAULT}                 (adapter only)
    #
    # {Dealing} answers 0, 6 and 7. Step 3 keys on the largest `**Size:**`
    # among plan.md's units ({Plans::UnitSizes}); a plan with none skips it.
    #
    # The adapter has the last word on the model, because it is the one that
    # knows the ceiling: a Claude agent asked for Fable runs on Opus, unless
    # the operator wrote Fable into `sizing:` ({Sizing#uncapped?}).
    #
    # @!attribute [r] adapter
    #   @return [OpenLanes::Adapters::Base]
    # @!attribute [r] model
    #   @return [String, nil]
    # @!attribute [r] effort
    #   @return [String, nil]
    Profile = Data.define(:adapter, :model, :effort) do
      # @return [String] e.g. `claude:opus/high`
      def to_s = "#{adapter.name}:#{model || "default"}#{"/#{effort}" if effort}"

      # What a narrow column shows: the model, prefixed by the adapter only
      # when it is not the default one.
      #
      # @return [String] e.g. `opus`, `codex:gpt-5-codex`
      def label
        name = model || "default"
        adapter.name == Adapters::DEFAULT ? name : "#{adapter.name}:#{name}"
      end
    end

    class Profile
      # @param agent [OpenLanes::Agents::Agent]
      # @param spec [OpenLanes::Plans::Spec, nil]
      # @param model [String, nil] what `run --model` typed
      # @param dealing [OpenLanes::Agents::Dealing] what `.openlanes.yml` gives
      #   an agent that names no adapter of its own
      # @return [OpenLanes::Agents::Profile]
      def self.resolve(agent, spec: nil, model: nil, dealing: Dealing.current)
        override = spec ? spec.override_for(agent.phase) : {}
        adapter = Adapters.for(dealing.replacement_for(agent) || override["adapter"] || agent.adapter || dealing.adapter_for(agent))
        # A model named for one CLI means nothing to another, so the agent's
        # own model is kept only on the CLI its frontmatter wrote it for,
        # which is the default one when it names none.
        own_model = adapter.name == (agent.adapter || Adapters::DEFAULT) ? agent.model : nil
        sized = sized(agent, spec)
        new(adapter:,
          model:   pick_model(adapter, model || override["model"] || (own_model unless sized[:model]), sized),
          effort:  override["effort"] || sized[:effort] || depth_effort(spec) || agent.effort)
      end

      # `.openlanes.yml` `sizing:` for the plan's largest unit, a builder only.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param spec [OpenLanes::Plans::Spec, nil]
      # @return [Hash{Symbol => Object}] `{model:, effort:, uncapped:}`; empty
      #   for an agent that does not build or a plan with no sized unit
      def self.sized(agent, spec)
        size = spec&.unit_size if Sizing::PHASES.include?(agent.phase.to_s)
        return {} unless size

        sizing = Config.current.sizing
        sizing.for(size).merge(uncapped: sizing.uncapped?(size))
      end

      # @param spec [OpenLanes::Plans::Spec, nil]
      # @return [String, nil]
      def self.depth_effort(spec) = spec&.depth && Plans::Spec::EFFORT_FOR_DEPTH[spec.depth]

      # Only a model `sizing:` chose may pass the ceiling: one typed or
      # written in the spec is capped as it always was.
      #
      # @return [String, nil]
      def self.pick_model(adapter, chosen, sized)
        return adapter.model(chosen) if chosen || !sized[:model]

        adapter.model(sized[:model], uncapped: sized[:uncapped])
      end
      private_class_method :sized, :depth_effort, :pick_model
    end
  end
end

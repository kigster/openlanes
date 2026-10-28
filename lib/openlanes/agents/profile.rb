# frozen_string_literal: true

module OpenLanes
  module Agents
    # Which coding agent runs an agent on a particular plan, on which model,
    # thinking how hard: the agent's own frontmatter, overridden by what the
    # plan's author asked for, overridden by what the operator typed.
    #
    # Precedence, highest first:
    #
    #   1. `run --model`                       (model only)
    #   2. spec.md `phases.<phase>`            (adapter, model, effort)
    #   3. spec.md `depth`                     (effort only)
    #   4. the agent's frontmatter
    #   5. `.openlanes.yml` `adapter:`         (adapter only, plan 040)
    #   6. {Adapters::DEFAULT}                 (adapter only)
    #
    # The adapter has the last word on the model, because it is the one that
    # knows the ceiling: a Claude agent asked for Fable runs on Opus.
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
      # @param project [String, nil] `.openlanes.yml` `adapter:`
      # @return [OpenLanes::Agents::Profile]
      def self.resolve(agent, spec: nil, model: nil, project: Config.current.adapter)
        override = spec ? spec.override_for(agent.phase) : {}
        adapter = Adapters.for(override["adapter"] || agent.adapter || project)
        # A model named for one CLI means nothing to another, so the agent's
        # own model is kept only on the CLI its frontmatter wrote it for,
        # which is the default one when it names none.
        own_model = adapter.name == (agent.adapter || Adapters::DEFAULT) ? agent.model : nil
        depth_effort = spec&.depth && Plans::Spec::EFFORT_FOR_DEPTH[spec.depth]
        new(adapter:,
          model:   adapter.model(model || override["model"] || own_model),
          effort:  override["effort"] || depth_effort || agent.effort)
      end
    end
  end
end

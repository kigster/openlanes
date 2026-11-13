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
    #   3. spec.md `depth`                     (effort only)
    #   4. the agent's frontmatter
    #   5. `.openlanes/config.yml` `review.adapters:` (adapter only, reviewers only, plan 031)
    #   6. `.openlanes/config.yml` `adapter:`         (adapter only, plan 040)
    #   7. {Adapters::DEFAULT}                 (adapter only)
    #
    # {Dealing} answers 0, 5 and 6.
    #
    # The adapter has the last word on the model, since a name means
    # something only to the CLI it is written for; today none of them
    # changes what it is handed.
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
      # @param dealing [OpenLanes::Agents::Dealing] what `.openlanes/config.yml` gives
      #   an agent that names no adapter of its own
      # @param diff_lines [Integer, nil] the plan's changed lines, insertions
      #   plus deletions; nil when unknown, and then no `small_diff:` applies
      # @return [OpenLanes::Agents::Profile]
      def self.resolve(agent, spec: nil, model: nil, dealing: Dealing.current, diff_lines: nil) # rubocop:disable Metrics/ParameterLists
        override = spec ? spec.override_for(agent.phase) : {}
        adapter = Adapters.for(dealing.replacement_for(agent) || override["adapter"] || agent.adapter || dealing.adapter_for(agent))
        # A model named for one CLI means nothing to another, so the agent's
        # own model is kept only on the CLI its frontmatter wrote it for,
        # which is the default one when it names none.
        native = adapter.name == (agent.adapter || Adapters::DEFAULT)
        # `small_diff:` stands in for the frontmatter, and so only where the
        # frontmatter would have had the last word: anything a person typed,
        # on the command line or in the spec, outranks it.
        small = native && model.nil? && override.empty? && agent.small_diff&.applies?(diff_lines) ? agent.small_diff : nil
        own_model = native ? (small&.model || agent.model) : nil
        depth_effort = spec&.depth && Plans::Spec::EFFORT_FOR_DEPTH[spec.depth]
        new(adapter:,
          model:   adapter.model(model || override["model"] || own_model),
          effort:  override["effort"] || depth_effort || small&.effort || agent.effort)
      end
    end
  end
end

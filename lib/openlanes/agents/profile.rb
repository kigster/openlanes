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
    #   3. `.openlanes/config.yml` `sizing:`   (model, effort; builders only, plan 060)
    #   4. spec.md `depth`                     (effort only)
    #   5. the agent's `by_quality:` for `desired_codebase_quality:` (model, effort)
    #   6. the agent's `small_diff:`           (model, effort)
    #   7. the agent's frontmatter, with `.openlanes/config.yml` `agents:` laid over it
    #      by {Registry}; a `model` or `effort` there also drops that key of step 5
    #   8. `.openlanes/config.yml` `review.adapters:` (adapter only, reviewers only, plan 031)
    #   9. `.openlanes/config.yml` `adapter:`         (adapter only, plan 040)
    #  10. {Adapters::DEFAULT}                 (adapter only)
    #
    # {Dealing} answers 0, 8 and 9. Step 3 keys on the largest `**Size:**`
    # among plan.md's units ({Plans::UnitSizes}); a plan with none skips it.
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
        quality = native ? by_quality(agent) : {}
        own_model = native ? (quality[:model] || small&.model || agent.model) : nil
        sized = sized(agent, spec, adapter)
        new(adapter:,
          model:   adapter.model(model || override["model"] || sized[:model] || own_model),
          effort:  override["effort"] || sized[:effort] || depth_effort(spec) || quality[:effort] || small&.effort || agent.effort)
      end

      # @param spec [OpenLanes::Plans::Spec, nil]
      # @return [String, nil] the effort spec.md's `depth` asks for
      def self.depth_effort(spec) = spec&.depth && Plans::Spec::EFFORT_FOR_DEPTH[spec.depth]
      private_class_method :depth_effort

      # The agent's `by_quality:` entry for the project's
      # `desired_codebase_quality:`. It names Claude's models, so the caller
      # asks only on the native CLI, like the frontmatter it stands in for.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @return [Hash{Symbol => String}] `{model:, effort:}`, empty when none applies
      def self.by_quality(agent) = agent.by_quality&.for(Config.current.desired_codebase_quality) || {}
      private_class_method :by_quality

      # `.openlanes/config.yml` `sizing:` for the plan's largest unit, a builder only.
      # The table names Claude's models, which mean nothing to another CLI,
      # so there it sets the effort alone.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param spec [OpenLanes::Plans::Spec, nil]
      # @param adapter [OpenLanes::Adapters::Base]
      # @return [Hash{Symbol => String}] `{model:, effort:}`; empty for an
      #   agent that does not build or a plan with no sized unit
      def self.sized(agent, spec, adapter)
        size = spec&.unit_size if Sizing::PHASES.include?(agent.phase.to_s)
        return {} unless size

        profile = Config.current.sizing.for(size)
        adapter.name == Adapters::DEFAULT ? profile : profile.except(:model)
      end
      private_class_method :sized
    end
  end
end

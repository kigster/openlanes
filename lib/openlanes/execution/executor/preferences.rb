# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What this run has been told about each agent beyond its definition:
      # a model chosen while it ran (W24), the reviewers running in place of
      # their own ({Replacements}), the `--model` and `--timeout` typed, and
      # from those the profile and the clock each invocation gets.
      class Preferences
        # Seconds an agent gets when neither its frontmatter nor `--timeout` says.
        DEFAULT_TIMEOUT = 1500

        # @param model [String, nil] what `run --model` typed
        # @param timeout [Integer, nil] what `run --timeout` typed
        # @param usable [#call] adapter name → whether the startup probe left it usable
        # @param replacements [OpenLanes::Execution::Executor::Replacements]
        def initialize(model:, timeout:, usable:, replacements: Replacements.new)
          @model = model
          @timeout = timeout
          @usable = usable
          @preferred = {}
          @replacements = replacements
        end

        # @return [OpenLanes::Execution::Executor::Replacements]
        attr_reader :replacements

        # Which CLI, model and effort this agent gets on this plan.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject, nil]
        # @param root [String] the checkout the agent runs in, whose diff a
        #   `small_diff:` model is chosen on. Under `--isolation worktree` that
        #   is the plan's worktree; the main tree sits on main and would measure
        #   every plan as a near-empty diff.
        # @return [OpenLanes::Agents::Profile]
        def profile_for(agent, subject = nil, root:)
          spec = subject ? Plans::Spec.for(subject) : nil
          replacing = subject ? @replacements.names(subject.feature.ordinal) : []
          Agents::Profile.resolve(agent,
            spec:,
            model:      preferred_model(agent, subject) || @model,
            dealing:    Agents::Dealing.current(usable: @usable, replacing:),
            diff_lines: diff_lines(agent, root))
        end

        # Counted only for an agent with a `small_diff:` model, since nothing
        # else reads it and every count is a git process.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @param root [String] the checkout to measure
        # @return [Integer, nil]
        def diff_lines(agent, root) = agent.small_diff && Vcs::DiffSize.lines(root)

        # A model a person chose for one agent on one plan while the run was
        # going (W24), taken from that agent's next invocation. It beats
        # `run --model` because it was said later, about this agent in
        # particular. nil forgets the choice.
        #
        # @param ordinal [#to_s]
        # @param agent [String] the agent's name
        # @param model [String, nil]
        # @return [void]
        def prefer_model(ordinal, agent, model)
          key = [ordinal.to_s, agent.to_s]
          model.nil? ? @preferred.delete(key) : @preferred[key] = model.to_s
        end

        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject, nil]
        # @return [String, nil]
        def preferred_model(agent, subject)
          subject && @preferred[[subject.feature.ordinal.to_s, agent.name]]
        end

        # The clock this agent runs against: the tighter of its own frontmatter
        # and `--timeout`. A flag that could only loosen was useless the day
        # somebody wanted a quick run.
        #
        # {DEFAULT_TIMEOUT} steps in only when neither names a figure. It used
        # to be the flag's default instead, which silently cut every 1200-second
        # agent to 900 on the runs where nobody had typed `--timeout` at all.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @return [Integer]
        def timeout_for(agent) = [agent.timeout, @timeout].compact.min || DEFAULT_TIMEOUT
      end
    end
  end
end

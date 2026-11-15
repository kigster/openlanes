# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What {Executor} answers about each agent's profile, clock and
      # replacement, from the run's {Preferences}. The including class holds
      # them as +@preferences+, and its checkout as +@root+.
      module Choices
        extend Forwardable

        # Which CLI, model and effort this agent gets on this plan.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject, nil]
        # @param root [String] the checkout the agent runs in
        # @return [OpenLanes::Agents::Profile]
        # @see Preferences#profile_for
        def profile_for(agent, subject = nil, root: @root) = @preferences.profile_for(agent, subject, root:)

        def_delegators :@preferences, :diff_lines, :prefer_model, :preferred_model, :timeout_for

        # @see Replacements#replace
        def replace(ordinal, agent, on: true) = @preferences.replacements.replace(ordinal, agent, on:)

        # @see Replacements#include?
        def replacing?(ordinal, agent) = @preferences.replacements.include?(ordinal, agent)

        # @see Replacements#end
        def end_replacements(ordinal) = @preferences.replacements.end(ordinal)
      end
    end
  end
end

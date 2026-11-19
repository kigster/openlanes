# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The reviewers on each plan that run on the main coding agent in
      # place of their dealt adapter, for this run.
      class Replacements
        def initialize = @replacing = Hash.new { |h, k| h[k] = Set.new }

        # @param ordinal [#to_s]
        # @return [Array<String>] the reviewers replaced on this plan
        def names(ordinal) = @replacing.fetch(ordinal.to_s, []).to_a

        # A reviewer that failed its round runs it again on the main coding
        # agent (D14 in plan 031), from its next invocation on this plan until
        # it is let go.
        #
        # @param ordinal [#to_s]
        # @param agent [String] the reviewer's name
        # @param on [Boolean] false lets it go back to its dealt adapter
        # @return [void]
        def replace(ordinal, agent, on: true)
          names = @replacing[ordinal.to_s]
          on ? names << agent.to_s : names.delete(agent.to_s)
        end

        # @param ordinal [#to_s]
        # @param agent [String]
        # @return [Boolean] whether the reviewer's run is a replacement
        def include?(ordinal, agent) = @replacing.fetch(ordinal.to_s, []).include?(agent.to_s)

        # A new review round opened, so a replacement owed to the last one is
        # not owed any more: every reviewer goes back to its dealt adapter.
        #
        # @param ordinal [#to_s]
        # @return [void]
        def end(ordinal) = @replacing.delete(ordinal.to_s)
      end
    end
  end
end

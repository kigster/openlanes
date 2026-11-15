# frozen_string_literal: true

module OpenLanes
  module Engine
    class Reviews
      # CI on a plan's pull requests, as a later review pass waits on it.
      # Says what it is waiting for once per answer, so a round that polls
      # every tick does not repeat itself. A run with no CI to ask does not
      # wait.
      class Build
        # @param builds [#call, nil] receives a subject and answers
        #   {Vcs::CiGate.verdict}; nil in a run that publishes nothing
        def initialize(builds)
          @builds = builds
          @said = {}
        end

        # @param subject [Plans::Subject]
        # @return [Boolean]
        def green?(subject)
          return true if @builds.nil?

          state = @builds.call(subject)
          ordinal = subject.feature.ordinal.to_s
          if state != :green && @said[ordinal] != state
            UI.log("review: the next reviewers wait for green CI, which is #{state}", plan: ordinal, level: state == :red ? :warn : :info)
          end
          @said[ordinal] = state
          state == :green
        end
      end
    end
  end
end

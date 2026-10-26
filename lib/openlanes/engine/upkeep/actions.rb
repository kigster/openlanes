# frozen_string_literal: true

module OpenLanes
  module Engine
    module Upkeep
      # What is done on GitHub, and in the plan's state, for each {Verdict}
      # that calls for something. The sweep decides; this only acts, and
      # owns every label and comment the sweep writes.
      class Actions
        # @param github [Vcs::GitHub]
        # @param clock [#call]
        def initialize(github:, clock:)
          @github = github
          @clock = clock
        end

        # Labelled `conflicts` beside its review label, with one comment.
        #
        # @param number [Integer]
        # @return [void]
        def conflicted(number)
          @github.swap_label(number:, add: Plans::ReviewLabel::CONFLICTS, remove: [Plans::ReviewLabel::CONFLICTS_RESOLVED.name])
          @github.comment(number:,
            body: "No longer merges clean onto `#{MAIN}`. Labelled `#{Plans::ReviewLabel::CONFLICTS}`; " \
                  "#{Agents::Names::REBASER} rebases it, and the review verdict stays.")
        end

        # Behind `main` without a conflict: GitHub rebases it, and the merge
        # waits for CI on the new head, which `rebased!` lets it know.
        #
        # @param subject [Plans::Subject]
        # @param number [Integer]
        # @return [String]
        def behind(subject, number)
          @github.update_branch(number:)
          Plans::PlanState.for(subject.feature.path).rebased!(number, at: @clock.call)
          "PR ##{number} was behind #{MAIN}; rebased on GitHub"
        end

        # @param number [Integer]
        # @return [String]
        def resolved(number)
          @github.swap_label(number:, add: Plans::ReviewLabel::CONFLICTS_RESOLVED, remove: [Plans::ReviewLabel::CONFLICTS.name])
          "PR ##{number} merges clean onto #{MAIN} again: #{Plans::ReviewLabel::CONFLICTS_RESOLVED}"
        end
      end
    end
  end
end

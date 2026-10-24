# frozen_string_literal: true

module OpenLanes
  module Engine
    module Upkeep
      # What the sweep owes one pull request, read from GitHub's answer
      # alone. No calls and no writes, so every case is a one-line example.
      #
      # - `:conflicted`: waiting to merge, `DIRTY`, not yet labelled `conflicts`
      # - `:still_conflicted`: `DIRTY` and labelled already; resolve, say nothing
      # - `:behind`: `BEHIND` without a conflict; GitHub can update it
      # - `:resolved`: labelled `conflicts`, and merges clean again
      # - `:unknown`: GitHub has not decided since `main` moved; ask again
      # - `:none`: closed, still in review (U2), or merging clean
      module Verdict
        module_function

        # @param live [Hash] {Vcs::GitHub#pull_request}'s answer
        # @return [Symbol]
        def of(live)
          return :none unless live[:open]

          labels = live[:labels]
          conflicted = labels.include?(Plans::ReviewLabel::CONFLICTS.name)
          return :none unless conflicted || Plans::ReviewLabel::WAITING.any? { labels.include?(it.name) }

          case live[:merge_state].to_s.upcase
          when "UNKNOWN" then :unknown
          when "DIRTY" then conflicted ? :still_conflicted : :conflicted
          when "BEHIND" then :behind
          else conflicted ? :resolved : :none
          end
        end
      end
    end
  end
end

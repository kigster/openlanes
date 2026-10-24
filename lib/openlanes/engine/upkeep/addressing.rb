# frozen_string_literal: true

module OpenLanes
  module Engine
    module Upkeep
      # Swaps `review-rejected` for `review-addressed` on every open pull
      # request whose head was committed after it was rejected (U1), by the
      # publisher or by anyone else. Left alone, the stale rejection read to
      # the PR watch as a fresh one, and a fixed pull request sat rejected
      # for good (#93, #83, #44).
      #
      # Every answer is read off GitHub as it stands, so it keeps no state
      # and may run on every poll.
      class Addressing
        # @param github [Vcs::GitHub]
        def initialize(github:)
          @github = github
        end

        # @return [Array<String>] one line per pull request relabelled or not readable
        def call
          rejected = Plans::ReviewLabel::REJECTED.name
          @github.open_pulls_labelled(rejected).filter_map do |number, _labels|
            address(number, rejected)
          rescue OpenLanes::Error => e
            "PR ##{number} not checked for fixes: #{Upkeep.first_line(e)}"
          end
        end

        private

        # @return [String, nil]
        def address(number, rejected)
          at = @github.labelled_at(number:, name: rejected) or return nil
          head = @github.head_committed_at(number:) or return nil
          return nil unless head > at

          addressed = Plans::ReviewLabel::ADDRESSED
          @github.swap_label(number:, add: addressed, remove: Plans::ReviewLabel.displaced_by(addressed))
          "PR ##{number} #{addressed}: committed #{head.iso8601}, after the rejection at #{at.iso8601}"
        end
      end
    end
  end
end

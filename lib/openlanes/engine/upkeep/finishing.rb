# frozen_string_literal: true

module OpenLanes
  module Engine
    module Upkeep
      # Takes `review-in-progress` off every pull request nobody is
      # reviewing any more: one that was merged or closed, and an open one
      # whose plan has left review. {Reviews} takes the label off when a
      # group of reviewers gives its verdict, but a pull request a person
      # merges under the reviewers, or one whose round ended with no verdict
      # at all, never reaches that line, and kept the label for good.
      #
      # Every answer is read off GitHub as it stands, so it keeps no state
      # and may run on every sweep.
      class Finishing
        # The states a plan's pull request is being reviewed in.
        REVIEWING = %i[ready_for_review in_review].freeze

        # @param github [Vcs::GitHub]
        def initialize(github:)
          @github = github
        end

        # @param subjects [Array<Plans::Subject>] the plans of this run
        # @return [Array<String>] one line per pull request relabelled, or not listed
        def call(subjects)
          name = Plans::ReviewLabel::IN_PROGRESS.name
          (@github.pulls_labelled(name, state: "closed").keys + left(name, subjects)).map do |number|
            @github.remove_label(number:, name:)
            "PR ##{number}: #{name} taken off, nobody is reviewing it"
          rescue OpenLanes::Error => e
            "PR ##{number} still #{name}: #{Upkeep.first_line(e)}"
          end
        end

        private

        # @return [Array<Integer>] the open pull requests still labelled
        #   +name+ whose plan has left review
        def left(name, subjects)
          reviewing = numbers(subjects.select { REVIEWING.include?(it.status.key) })
          left = numbers(subjects) - reviewing
          left.empty? ? [] : @github.open_pulls_labelled(name).keys & left
        end

        # @param subjects [Array<Plans::Subject>]
        # @return [Array<Integer>] their open pull requests
        def numbers(subjects)
          subjects.flat_map { |subject| subject.pull_requests.select(&:open?).map { Vcs::GitHub.number_of(it.url || it.number.to_s) } }
        end
      end
    end
  end
end

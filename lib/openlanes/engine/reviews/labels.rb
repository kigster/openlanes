# frozen_string_literal: true

module OpenLanes
  module Engine
    class Reviews
      # What a review round says on the plan's pull requests. A `gh` failure
      # is logged, never raised: the round is decided either way, and the
      # label is the decision's echo.
      class Labels
        # @param review [Vcs::Review, nil] nil in a run that publishes
        #   nothing, which has no pull request to label
        def initialize(review)
          @review = review
        end

        # Puts +labels+ on every open pull request of +subject+, stopping at
        # the first refusal.
        #
        # @param subject [Plans::Subject]
        # @param labels [Array<Plans::ReviewLabel>]
        # @return [String, nil] why a passing label was refused
        def put(subject, labels)
          return if @review.nil?

          pulls(subject).each do |pull|
            refused = refusal(pull, labels) and return refused
          end
          nil
        rescue Error => e
          UI.log("could not label #{subject.feature.ordinal}: #{e.message}", level: :warn, plan: subject.feature.ordinal.to_s)
          nil
        end

        # @param subject [Plans::Subject]
        # @return [void] `review-in-progress` off every open pull request
        def finish(subject)
          return if @review.nil?

          pulls(subject).each { @review.finish(pr: it.url || it.number) }
          nil
        rescue Error => e
          UI.log("could not take #{Plans::ReviewLabel::IN_PROGRESS} off #{subject.feature.ordinal}: #{e.message}",
            level: :warn,
            plan:  subject.feature.ordinal.to_s)
        end

        private

        # @return [Array<Plans::PullRequest>]
        def pulls(subject) = subject.pull_requests.select(&:open?)

        # @param pull [Plans::PullRequest]
        # @param labels [Array<Plans::ReviewLabel>]
        # @return [String, nil] why the first refused label was refused
        def refusal(pull, labels)
          labels.each do |label|
            result = @review.call(pr: pull.url || pull.number, label: label.name)
            return "##{result.pr} #{result.reason}" if result.refused?
          end
          nil
        end
      end
    end
  end
end

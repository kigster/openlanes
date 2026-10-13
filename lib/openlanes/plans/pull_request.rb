# frozen_string_literal: true

module OpenLanes
  module Plans
    # One row of a plan's `pull-requests.md`.
    #
    # @!attribute [r] number
    #   @return [String, nil] as written, without the `#`
    # @!attribute [r] title
    #   @return [String]
    # @!attribute [r] url
    #   @return [String, nil]
    # @!attribute [r] state
    #   @return [String] normalised words plus emoji, e.g. "Open 🟡"
    PullRequest = Data.define(:number, :title, :url, :state) do
      # Still awaiting a decision. A closed-unmerged pull request is finished
      # business, so it is neither open nor merged.
      #
      # @return [Boolean]
      def open? = state.match?(/\b(?:open|wip|draft)\b/i)

      # @return [Boolean]
      def merged? = state.match?(/\bmerged\b/i) && !state.match?(/\bunmerged\b/i)

      # @return [String] "#92 — Send mail through Resend"
      def label = number ? "##{number} — #{title}" : title
    end
  end
end

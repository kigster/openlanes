# frozen_string_literal: true

require "aasm"

module OpenLanes
  module Plans
    # The state machine for one pull request (decision P2).
    #
    # A plan's state is the emoji in its folder name; a pull request's is the
    # {ReviewLabel} it carries on GitHub. A plan may have several pull
    # requests, each somewhere else in review, so the two machines are kept
    # apart: {StateMachine} moves folders, this one says which label may
    # follow which. Like {StateMachine}, it keeps no state of its own. It is
    # read off the labels and the row's GitHub state, and the caller makes
    # the change on GitHub through {Vcs::Review} or {Vcs::GitHub}.
    #
    # `merged` and `closed` are not labels. They are GitHub's own states,
    # and they outrank any label still on the pull request.
    class PullRequestMachine
      include AASM

      # Raised when a move is refused, naming both ends.
      class Refused < Error; end

      # Label name => state key: `ready-to-merge` is `:ready_to_merge`.
      #
      # @param name [String]
      # @return [Symbol]
      def self.key_for(name) = name.to_s.tr("-", "_").to_sym

      # The state with no label on it yet: opened before the publisher
      # labelled it, or by a person.
      UNLABELLED = :unlabelled

      aasm do
        state UNLABELLED, initial: true
        ReviewLabel::ALL.each { |label| state PullRequestMachine.key_for(label.name) }
        state :merged
        state :closed

        event :submit do
          transitions from: %i[unlabelled review_rejected review_vulnerability], to: :ready_for_review
        end

        # Fixes reached a rejected pull request (U1). The harness fires it,
        # whoever pushed them.
        event :address do
          transitions from: %i[review_rejected review_vulnerability], to: :review_addressed
        end

        event :start_review do
          transitions from: %i[unlabelled ready_for_review review_addressed], to: :review_in_progress
        end

        # The reviewers' verdicts, and verifier's rejection after them. A
        # rejection also reaches back from `ready-to-merge` and
        # `merge-manually`: a pull request that no longer rebases onto
        # `main` after its sibling merged goes back to the builders (P5), and
        # a person may reject one they were asked to merge.
        event :reject do
          transitions from: %i[review_in_progress review_passed review_approved ready_to_merge merge_manually],
            to: :review_rejected
        end

        event :flag_vulnerability do
          transitions from: %i[review_in_progress review_rejected], to: :review_vulnerability
        end

        event :pass_with_doubts do
          transitions from: %i[review_in_progress], to: :review_passed
        end

        event :approve do
          transitions from: %i[review_in_progress], to: :review_approved
        end

        # verifier verified it, CI is green and the coverage gate holds.
        event :ready do
          transitions from: %i[review_passed review_approved], to: :ready_to_merge
        end

        # deploy-assessor's two verdicts, as the engine acted on them. Only a
        # `ready-to-merge` pull request is ruled on.
        event :merge_automatically do
          transitions from: %i[ready_to_merge], to: :auto_merged
        end

        event :leave_for_a_person do
          transitions from: %i[ready_to_merge], to: :merge_manually
        end

        # GitHub's own states. A person may merge or close at any point; an
        # `auto-merged` pull request is merged already.
        event :merged do
          transitions from: ReviewLabel::ALL.map { PullRequestMachine.key_for(it.name) } + [UNLABELLED], to: :merged
        end

        event :close do
          transitions from: (ReviewLabel::ALL.map { PullRequestMachine.key_for(it.name) } - %i[auto_merged]) + [UNLABELLED],
            to: :closed
        end
      end

      # Where a pull request stands, from its row and its labels. GitHub's
      # merged or closed wins over any label; among labels, the one furthest
      # along {ReviewLabel::ALL} wins, since a stale verdict left beside a
      # newer one is the older of the two.
      #
      # @param pull [PullRequest] its row in `pull-requests.md`
      # @param labels [Array<String>] its labels on GitHub now
      # @return [Symbol]
      def self.state_of(pull, labels)
        return :merged if pull.merged?
        return :closed unless pull.open?

        label = ReviewLabel::ALL.rfind { labels.include?(it.name) }
        label ? key_for(label.name) : UNLABELLED
      end

      # @param pull [PullRequest]
      # @param labels [Array<String>]
      def initialize(pull, labels)
        @pull = pull
        @key = self.class.state_of(pull, labels)
      end

      # @return [PullRequest]
      attr_reader :pull

      # @return [Symbol] the state right now
      attr_reader :key

      # AASM keeps state in a column; this one is read off GitHub, and a move
      # is only ever asked about, never stored here.
      #
      # @return [Symbol]
      def aasm_read_state(_name = :default) = @key

      # @return [Boolean]
      def aasm_write_state(new_state, name = :default) = aasm_write_state_without_persistence(new_state, name)

      # @return [Boolean]
      def aasm_write_state_without_persistence(new_state, _name = :default)
        @key = new_state
        true
      end

      # @return [Boolean] whether deploy-assessor's verdict has been acted on (P2)
      def complete? = %i[auto_merged merge_manually].include?(key)

      # @param event [Symbol]
      # @return [Boolean] whether +event+ may fire from here
      def may?(event) = aasm.may_fire_event?(event)

      # Take one step, so the caller learns the move is legal before it
      # changes anything on GitHub.
      #
      # @param event [Symbol]
      # @return [Symbol] the state now occupied
      # @raise [Refused] when the move is not in the topology
      def fire!(event)
        raise Refused, "PR ##{pull.number.to_s.delete("#")} is #{key}; #{event} does not apply" unless may?(event)

        aasm.fire!(event)
        key
      end
    end
  end
end

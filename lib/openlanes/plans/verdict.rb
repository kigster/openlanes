# frozen_string_literal: true

module OpenLanes
  module Plans
    # The review label the reviewers' verdicts add up to (decisions V2 and V4
    # in docs/decisions/decisions-on-agent-names-models-and-reviewers.md).
    #
    # Each reviewer reports one verdict in its closing ledger note: `great`,
    # `passed` or `rejected`. Once every reviewer has reported: any rejection
    # rejects (and `security-reviewer`'s `vulnerability` adds
    # {ReviewLabel::VULNERABILITY} beside it); otherwise a majority of `great`
    # approves; otherwise {ReviewLabel::PASSED}. With three reviewers that is
    # two `great` of three, and an odd count (V5) never ties.
    #
    # This replaced R3's pooled emoji count: the comments still open with
    # their emoji, for the person reading them, but the reviewers' own
    # verdicts decide the label.
    #
    # Pure: it reads notes and answers labels, and nothing here reads GitHub.
    #
    # @!attribute [r] labels
    #   @return [Array<ReviewLabel>] one verdict, or {ReviewLabel::REJECTED}
    #     and {ReviewLabel::VULNERABILITY} together
    # @!attribute [r] votes
    #   @return [Array<Vote>] the verdicts counted
    # @!attribute [r] ignored
    #   @return [Array<Vote>] votes claiming a vulnerability from a reviewer
    #     other than {SECURITY_REVIEWER}; counted as plain rejections
    Verdict = Data.define(:labels, :votes, :ignored) do
      # @return [Boolean] whether the labels let the pull request go on
      def passing? = labels.all?(&:passing?)

      # @return [Array<String>] the label names, as `openlanes review` takes them
      def names = labels.map(&:name)
    end

    class Verdict
      # One reviewer's verdict. The agent has to be carried alongside it:
      # every reviewer comments from the same GitHub account (R2), so nothing
      # on GitHub says which reviewer said what.
      #
      # @!attribute [r] agent
      #   @return [String] the reviewer's name
      # @!attribute [r] word
      #   @return [Symbol] one of {WORDS}
      # @!attribute [r] vulnerability
      #   @return [Boolean] the reviewer found an exploitable hole
      Vote = Data.define(:agent, :word, :vulnerability) do
        alias_method :vulnerability?, :vulnerability

        # @return [Boolean]
        def great? = word == :great

        # @return [Boolean]
        def rejected? = word == :rejected
      end

      # What a reviewer may say, best first.
      WORDS = %i[great passed rejected].freeze

      # A closing note's first word, and the verdict it reports. `approved`
      # is `great` under the name staff-reviewer signed before V2; `slop`
      # sends the plan to be rewritten, and so counts as a rejection.
      NOTE_WORDS = {
        "great" => :great, "approved" => :great, "passed" => :passed, "rejected" => :rejected, "slop" => :rejected
      }.freeze

      # Anchored, as {Arbitration::Counter::REJECTION} is: "nothing to
      # reject" is not a rejection, and "great, nothing to reject" is great.
      NOTE = /\A\W*(#{NOTE_WORDS.keys.join("|")})\b/i

      # What marks a rejection as a security hole.
      VULNERABILITY = /\bvulnerab/i

      # The one reviewer whose `vulnerability` counts. From anyone else it
      # would put {ReviewLabel::VULNERABILITY} on a pull request on a
      # reviewer's say-so outside its remit.
      SECURITY_REVIEWER = Agents::Names::SECURITY_REVIEWER

      class << self
        # @param votes [Array<Vote>] one per reviewer that reported
        # @return [Verdict]
        # @raise [ArgumentError] when there are no votes: no verdict yet
        def call(votes)
          raise ArgumentError, "no reviewer has reported a verdict" if votes.empty?

          ignored = votes.select { it.vulnerability? && it.agent.to_s != SECURITY_REVIEWER }
          new(labels: labels_for(votes, ignored), votes:, ignored:)
        end

        # The verdict a reviewer's closing ledger note reports (D1 of plan 031).
        #
        # @example
        #   Verdict.vote(agent: "security-reviewer", note: "rejected 1/2 vulnerability")
        #   # => #<data Vote agent="security-reviewer", word=:rejected, vulnerability=true>
        #
        # @param agent [String] the reviewer
        # @param note [String, nil] the ledger entry's note
        # @return [Vote, nil] nil for a note that reports no verdict
        def vote(agent:, note:)
          word = NOTE_WORDS[note.to_s[NOTE, 1].to_s.downcase] or return

          Vote.new(agent:, word:, vulnerability: word == :rejected && note.match?(VULNERABILITY))
        end

        private

        # @return [Array<ReviewLabel>]
        def labels_for(votes, ignored)
          if votes.any?(&:rejected?)
            flaw = (votes - ignored).any?(&:vulnerability?)
            [ReviewLabel::REJECTED, *(ReviewLabel::VULNERABILITY if flaw)]
          elsif votes.count(&:great?) * 2 > votes.size
            [ReviewLabel::APPROVED]
          else
            [ReviewLabel::PASSED]
          end
        end
      end
    end
  end
end

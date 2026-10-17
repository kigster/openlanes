# frozen_string_literal: true

module OpenLanes
  module Plans
    # The review label the reviewers' comments add up to (decisions R2, R3).
    #
    # Every review comment opens with an emoji that declares how much it
    # matters. Counted across all the reviewers together, in order: any ⛔️ or
    # 💣 rejects (and a 💣 adds {ReviewLabel::VULNERABILITY} beside the
    # rejection); otherwise more than `max_hmm` 🤔 is
    # {ReviewLabel::OK_NOT_PERFECT}; otherwise {ReviewLabel::APPROVED}. A clean
    # small pull request is approved even if it earned no ✅.
    #
    # Pure: it reads strings and answers labels. The threshold comes in as an
    # argument, so where it is configured ({Config#max_hmm}) is not this
    # class's business, and nothing here reads GitHub.
    #
    # @!attribute [r] labels
    #   @return [Array<ReviewLabel>] one verdict, or {ReviewLabel::REJECTED}
    #     and {ReviewLabel::VULNERABILITY} together
    # @!attribute [r] tally
    #   @return [Hash{Symbol => Integer}] counted comments, by {MARKS} key
    # @!attribute [r] ignored
    #   @return [Array<Comment>] 💣 or 🔓 comments from a reviewer other than
    #     {SECURITY_REVIEWER}, left out of the tally
    Verdict = Data.define(:labels, :tally, :ignored) do
      # @return [Boolean] whether the labels let the pull request go on
      def passing? = labels.all?(&:passing?)

      # @return [Array<String>] the label names, as `openlanes review` takes them
      def names = labels.map(&:name)
    end

    class Verdict
      # One review comment, and the agent that wrote it. The author has to be
      # carried alongside the body: every reviewer comments from the same
      # GitHub account (R2), so GitHub's author says nothing about who wrote it.
      Comment = Data.define(:agent, :body)

      # The opening emoji, by what they mean. ⛔ is matched with and without
      # its variation selector (U+FE0F), since editors and models drop it as
      # often as they keep it; the others tolerate a stray one too.
      MARKS = {
        great:    "\u2705",    # ✅ Great!
        hmm:      "\u{1F914}", # 🤔 Hmmm...
        must_fix: "\u26D4",    # ⛔️ Must Fix, with or without U+FE0F after it
        flaw:     "\u{1F4A3}", # 💣 Security Flaw
        concern:  "\u{1F513}"  # 🔓 Security Concern
      }.freeze

      # The words each emoji is written with, for a person reading the tally.
      WORDS = {
        great: "Great!", hmm: "Hmmm...", must_fix: "Must Fix", flaw: "Security Flaw", concern: "Security Concern"
      }.freeze

      # Marks only the security reviewer may use. From anyone else a 💣 would
      # reject a pull request on a reviewer's say-so outside its remit, so it
      # is dropped and reported rather than counted.
      SECURITY_MARKS = %i[flaw concern].freeze

      # The one agent whose 💣 and 🔓 count.
      SECURITY_REVIEWER = "vader-security-reviewer"

      # How many 🤔 a review may carry and still be approved.
      DEFAULT_MAX_HMM = 5

      # Markdown a comment may open with before its emoji: a heading, a
      # quote, bold. Anything else first means the comment declares nothing.
      LEAD = /\A[\s#>*_]*/

      class << self
        # @param comments [Array<Comment, Hash>] each with `agent:` and `body:`
        # @param max_hmm [Integer] the most 🤔 an approval may carry
        # @return [Verdict]
        def call(comments, max_hmm: DEFAULT_MAX_HMM)
          tally = MARKS.keys.to_h { [it, 0] }
          ignored = []
          comments.each do |raw|
            comment = coerce(raw)
            mark = mark_of(comment.body)
            next if mark.nil?

            if SECURITY_MARKS.include?(mark) && comment.agent.to_s != SECURITY_REVIEWER
              ignored << comment
              next
            end
            tally[mark] += 1
          end
          new(labels: labels_for(tally, max_hmm), tally:, ignored:)
        end

        # The mark a comment opens with.
        #
        # @param body [String]
        # @return [Symbol, nil] a {MARKS} key; nil for a comment that declares
        #   nothing, such as the "Reviewed by ..." header
        def mark_of(body)
          text = body.to_s.sub(LEAD, "")
          MARKS.find { |_, emoji| text.start_with?(emoji) }&.first
        end

        private

        # @return [Comment]
        def coerce(raw)
          return raw if raw.is_a?(Comment)

          Comment.new(agent: raw[:agent] || raw["agent"], body: raw[:body] || raw["body"])
        end

        # @return [Array<ReviewLabel>]
        def labels_for(tally, max_hmm)
          if tally[:must_fix].positive? || tally[:flaw].positive?
            [ReviewLabel::REJECTED, *(ReviewLabel::VULNERABILITY if tally[:flaw].positive?)]
          elsif tally[:hmm] > max_hmm
            [ReviewLabel::OK_NOT_PERFECT]
          else
            [ReviewLabel::APPROVED]
          end
        end
      end
    end
  end
end

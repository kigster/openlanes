# frozen_string_literal: true

module OpenLanes
  module Arbitration
    # The only code that acts on a ruling (M7): it records it in
    # `state.json`, posts the engine's comment on the pull request, sets the
    # label through {Vcs::Review} (which refuses a passing label while CI is
    # red or pending), moves the plan, writes `blocked.md` for a `cap/no_go`,
    # and mails who must hear of it. The agent did none of this.
    class Effects
      # What a ruling did.
      #
      # @!attribute [r] ruling
      #   @return [Hash] as recorded in `state.json`
      # @!attribute [r] label
      #   @return [String, nil] the label set, nil when none was asked or it was refused
      # @!attribute [r] refused
      #   @return [String, nil] why {Vcs::Review} refused the label
      # @!attribute [r] to
      #   @return [Symbol, nil] the state the plan moved to
      # @!attribute [r] mailed
      #   @return [Array<String>]
      Result = Data.define(:ruling, :label, :refused, :to, :mailed)

      # Who signs the engine's mail about a ruling.
      SENDER = AGENT

      # @param tree_dir [String] the `.plans` directory
      # @param github [OpenLanes::Vcs::GitHub]
      # @param review [OpenLanes::Vcs::Review]
      # @param clock [#call]
      def initialize(tree_dir:, github:, review: Vcs::Review.new(github:), clock: -> { Time.now })
        @tree_dir = tree_dir
        @github = github
        @review = review
        @clock = clock
      end

      # @param plan [OpenLanes::Plans::Subject]
      # @param ruling [Ruling]
      # @param round [Integer, nil]
      # @param trigger [String]
      # @param appellant [String, nil] who appealed, for an appeal
      # @param sha [String, nil] the head a passed_check ruled on
      # @return [Result]
      def apply(plan:, ruling:, trigger:, round: nil, appellant: nil, sha: nil)
        recorded = Plans::PlanState.for(plan.feature.path)
                                   .rule!(kind: ruling.kind,
                                     pr: ruling.pr,
                                     round:,
                                     outcome: ruling.outcome,
                                     findings: ruling.findings,
                                     winner: ruling.winner,
                                     reason: ruling.reason,
                                     trigger:,
                                     sha:,
                                     at: @clock.call)
        label, refused = labelled(ruling)
        # blocked.md first: ⭕️'s invariant asks for an open question before
        # the machine lets the plan in.
        write_blocked(plan, ruling) if [ruling.kind, ruling.outcome] == %w[cap no_go]
        to = move(plan, ruling, refused)
        mailed = mail(plan, ruling, appellant)
        comment(ruling, label, refused)
        Result.new(ruling: recorded, label:, refused:, to:, mailed:)
      end

      private

      # @return [Array(String, String)] the label set and why it was refused
      def labelled(ruling)
        name = label_for(ruling) or return [nil, nil]
        return [nil, "no pull request to label"] unless ruling.pr

        result = @review.call(pr: ruling.pr, label: name)
        result.refused? ? [nil, result.reason] : [name, nil]
      rescue Error => e
        [nil, e.message]
      end

      # @return [String, nil]
      def label_for(ruling)
        # Struck with nothing critical left is a review with no findings.
        return Plans::ReviewLabel::READY_TO_MERGE.name if [ruling.kind, ruling.outcome] == %w[appeal struck] && ruling.critical.empty?

        case [ruling.kind, ruling.outcome]
        in ["cap", "go"] | ["passed_check", "too_harsh"] then Plans::ReviewLabel::READY_TO_MERGE.name
        in ["passed_check", "too_lenient"] then Plans::ReviewLabel::REJECTED.name
        else nil
        end
      end

      # A refused label leaves the plan where it is too: moving it without
      # the label would show a state GitHub does not.
      #
      # @return [Symbol, nil]
      def move(plan, ruling, refused)
        to = case [ruling.kind, ruling.outcome]
             in ["cap", "go"] then :ready_for_review
             in ["cap", "no_go"] then :blocked
             in ["passed_check", "too_lenient"] then :rejected
             else nil
             end
        return nil if to.nil? || (refused && to != :blocked)

        subject = find(plan) or return nil
        return nil unless subject.machine.may?(to)

        subject.machine.promote!(to)
        to
      rescue Plans::StateMachine::Refused
        nil
      end

      # @return [void]
      def write_blocked(plan, ruling)
        subject = find(plan) or return
        File.write(File.join(subject.feature.path, "blocked.md"), <<~MD)
          # Blocked

          ## B1 The arbitrator ruled no_go at the rejection cap

          #{ruling.headline}

          > #{ruling.reason.gsub("\n", "\n> ")}

          a) Send it back to the builders for one more round. (Recommended)
          b) Close the pull request and replan.
        MD
      end

      # @return [Array<String>]
      def mail(plan, ruling, appellant)
        to = case ruling.kind
             when "appeal" then [appellant, ("hansolo-reviewer" if ruling.outcome == "struck")]
             when "dispute" then %w[luke-backend rey-frontend]
             when "passed_check" then ruling.outcome == "too_lenient" ? %w[luke-backend rey-frontend] : []
             else []
             end
        to = to.compact.uniq
        subject = find(plan) or return []
        body = [ruling.headline, ruling.reason, struck_line(ruling)].compact.join("\n\n")
        to.each { Plans::Mailbox.new(dir: subject.feature.path).append(from: SENDER, to: it, body:) }
        to
      end

      # @return [void]
      def comment(ruling, label, refused)
        return unless ruling.pr

        body = [ruling.headline, "> #{ruling.reason.gsub("\n", "\n> ")}", struck_line(ruling),
                ("Label set: `#{label}`." if label),
                ("Label not set: #{refused}. The plan stays where it is." if refused)].compact.join("\n\n")
        @github.comment(number: ruling.pr, body:)
      end

      # @return [String, nil]
      def struck_line(ruling) = ruling.struck.empty? ? nil : "Struck: #{ruling.struck.join(", ")}."

      # @return [OpenLanes::Plans::Subject, nil] the plan as it stands now
      def find(plan) = Plans::Tree.new(dir: @tree_dir).find(plan.feature.ordinal.to_s)
    end
  end
end

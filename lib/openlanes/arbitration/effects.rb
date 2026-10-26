# frozen_string_literal: true

module OpenLanes
  module Arbitration
    # The only code that acts on a ruling (M7): it records it in
    # `state.json`, posts the engine's comment on the pull request, sets the
    # label through {Vcs::Review} (which refuses a passing label while CI is
    # red or pending), moves the plan, writes `blocked.md` for a `cap/no_go`,
    # and mails who must hear of it. The agent did none of this, and the
    # pull request acted on is always the plan's own, whatever `pr:` says.
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
      # @return [Result]
      def apply(plan:, ruling:, trigger:, round: nil, appellant: nil)
        pr, astray = own_pull(plan, ruling)
        recorded = Plans::PlanState.for(plan.feature.path)
                                   .rule!(kind: ruling.kind,
                                     pr:,
                                     round:,
                                     outcome: ruling.outcome,
                                     findings: ruling.findings,
                                     winner: ruling.winner,
                                     reason: ruling.reason,
                                     trigger:,
                                     review: review_round(plan),
                                     at: @clock.call)
        to = destination(ruling)
        # Asked before the label: a label set for a move the machine cannot
        # make shows on GitHub a state the folder never reaches.
        refused = astray || unreachable(plan, to)
        label, refused = labelled(ruling, pr) unless refused
        to = move(plan, ruling, to, refused)
        mailed = mail(plan, ruling, appellant)
        comment(pr, ruling, label, refused)
        Result.new(ruling: recorded, label:, refused:, to:, mailed:)
      end

      private

      # The plan's own open pull request, and why the ruling's `pr:` was set
      # aside when it names another. The ruling is model output: a prompt
      # injected into a diff could have it name any pull request, and the
      # engine labels and comments only on the one this plan opened.
      #
      # @return [Array(Integer, String)] the number, nil when the plan has
      #   none open, and the reason, nil when the ruling agreed
      def own_pull(plan, ruling)
        pull = plan.pull_requests.select(&:open?).last
        own = pull && Integer(Vcs::GitHub.number_of(pull.url || pull.number), exception: false)
        return [own, nil] if ruling.pr.nil? || ruling.pr == own

        [own, "the ruling names PR ##{ruling.pr}, not this plan's #{own ? "##{own}" : "(none open)"}"]
      end

      # @return [Integer, nil] the round of staff-reviewer's latest review, which
      #   the finding ids in this ruling belong to
      def review_round(plan)
        Plans::PlanState.for(plan.feature.path).signatures
                        .select { it["agent"] == Agents::Names::STAFF_REVIEWER && it["status"] == "Completed" }.last&.fetch("round", nil)
      end

      # @return [String, nil] why the plan cannot go where the ruling sends it
      def unreachable(plan, to)
        return nil if to.nil?

        subject = find(plan) or return "the plan is gone"
        from = subject.status.key
        Plans::StateMachine.edge?(from, to) ? nil : "a plan at #{from} cannot move to #{to}"
      end

      # @return [Array(String, String)] the label set and why it was refused
      def labelled(ruling, pr) # rubocop:disable Naming/MethodParameterName -- the ruling's own key
        name = label_for(ruling) or return [nil, nil]
        return [nil, "no pull request to label"] unless pr

        result = @review.call(pr:, label: name)
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

      # @return [Symbol, nil] where the ruling sends the plan
      def destination(ruling)
        case [ruling.kind, ruling.outcome]
        in ["cap", "go"] then :ready_for_review
        in ["cap", "no_go"] then :blocked
        in ["passed_check", "too_lenient"] then :rejected
        else nil
        end
      end

      # A refused label leaves the plan where it is too: moving it without
      # the label would show a state GitHub does not. ⭕️ carries no label,
      # so a `cap/no_go` blocks whatever GitHub said.
      #
      # @return [Symbol, nil]
      def move(plan, ruling, to, refused)
        return nil if to.nil? || (refused && to != :blocked)

        subject = find(plan) or return nil
        return (OpenLanes::Arbitration.block(subject, blocked_md(ruling)) ? to : nil) if to == :blocked
        return nil unless subject.machine.may?(to)

        subject.machine.promote!(to)
        to
      rescue Plans::StateMachine::Refused
        nil
      end

      # @return [String]
      def blocked_md(ruling)
        <<~MD
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
             when "appeal" then [appellant, (Agents::Names::STAFF_REVIEWER if ruling.outcome == "struck")]
             when "dispute" then Agents::Names::BUILDERS
             when "passed_check" then ruling.outcome == "too_lenient" ? Agents::Names::BUILDERS : []
             else []
             end
        to = to.compact.uniq
        subject = find(plan) or return []
        body = [ruling.headline, ruling.reason, struck_line(ruling)].compact.join("\n\n")
        to.each { Plans::Mailbox.new(dir: subject.feature.path).append(from: SENDER, to: it, body:) }
        to
      end

      # @return [void]
      def comment(pr, ruling, label, refused) # rubocop:disable Naming/MethodParameterName -- the ruling's own key
        return unless pr

        body = [ruling.headline, "> #{ruling.reason.gsub("\n", "\n> ")}", struck_line(ruling),
                ("Label set: `#{label}`." if label),
                ("Label not set: #{refused}. The plan stays where it is." if refused)].compact.join("\n\n")
        @github.comment(number: pr, body:)
      end

      # @return [String, nil]
      def struck_line(ruling) = ruling.struck.empty? ? nil : "Struck: #{ruling.struck.join(", ")}."

      # @return [OpenLanes::Plans::Subject, nil] the plan as it stands now
      def find(plan) = Plans::Tree.new(dir: @tree_dir).find(plan.feature.ordinal.to_s)
    end
  end
end

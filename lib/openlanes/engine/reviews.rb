# frozen_string_literal: true

module OpenLanes
  module Engine
    # One review round of a plan's pull request: who reviews it, what each
    # reviewer said, and what that adds up to once the last one has spoken
    # (decisions V2, V4 and V5 in
    # docs/decisions/decisions-on-agent-names-models-and-reviewers.md).
    #
    # Each reviewer's verdict is written on its own stage in `state.json`,
    # so the round survives a restart: a reviewer that finished before the
    # engine stopped still counts after it starts again. A round is named by
    # the plan's `moves` when its verdicts were given, written beside each
    # one as `review`: every way out of review moves the folder, so the next
    # round starts with a count of its own. The stage's own `moves` will not
    # do, since it is written as the stage settles, after the last reviewer
    # has already moved the folder.
    #
    # Only this class labels the pull request for a verdict. A reviewer
    # reports, never labels, so three reviewers cannot race each other's
    # labels, and the label always says what the round said.
    class Reviews
      # An agent with this `phase:` is a reviewer.
      PHASE = "review"

      # The state every reviewer works the pull request in.
      STATE = :in_review

      # What a round came to.
      #
      # @!attribute [r] verdict
      #   @return [Plans::Verdict, nil] nil while reviewers are still to report
      # @!attribute [r] pending
      #   @return [Array<String>] the reviewers still to report
      # @!attribute [r] target
      #   @return [Symbol, nil] `:approved`, `:rejected` or `:slop`; nil while pending
      # @!attribute [r] note
      #   @return [String] one line for the attempt
      Decision = Data.define(:verdict, :pending, :target, :note) do
        # @return [Boolean]
        def pending? = !pending.empty?
      end

      # A note that sends the plan to be rewritten, not back to its builders.
      SLOP = /\A\W*slop\b/i

      # @param agents [Agents::Registry]
      # @param review [Vcs::Review, nil] labels the pull request; nil in a run
      #   that publishes nothing, which has no pull request to label
      def initialize(agents:, review: nil)
        @agents = agents
        @review = review
      end

      # @param agent [Agents::Agent]
      # @return [Boolean]
      def reviewer?(agent) = agent.phase.to_s == PHASE

      # The reviewers this plan gets: every reviewer whose `starts:` serves
      # the plan's (V5), so a `starts: building` plan gets one.
      #
      # @param subject [Plans::Subject]
      # @return [Array<Agents::Agent>]
      def reviewers(subject)
        Agents::Routing.filter(@agents.for_status(Plans::STATUS_BY_KEY.fetch(STATE)), subject).select { reviewer?(it) }
      end

      # Counts +note+ as +agent+'s verdict, beside the round's others.
      #
      # @param subject [Plans::Subject]
      # @param agent [Agents::Agent]
      # @param note [String] the closing ledger note
      # @return [Decision, nil] nil when the note reports no verdict
      def decide(subject, agent, note)
        vote = Plans::Verdict.vote(agent: agent.name, note:) or return

        notes = round(subject).merge(agent.name => note)
        pending = reviewers(subject).map(&:name) - notes.keys
        return Decision.new(verdict: nil, pending:, target: nil, note: "#{vote.word}; waiting for #{pending.join(", ")}") unless pending.empty?

        decided(notes)
      end

      # Writes +note+ on +agent+'s stage as its verdict in the plan's
      # current review round, before anything is decided from it.
      #
      # @param subject [Plans::Subject]
      # @param agent [Agents::Agent]
      # @param round [Integer] the agent's own round
      # @param note [String]
      # @return [void]
      def vote!(subject, agent, round, note)
        state = Plans::PlanState.for(subject.feature.path)
        state.stage!(agent: agent.name, round:, verdict: note, review: state.read["moves"].to_i)
        nil
      end

      # Puts +labels+ on every open pull request of +subject+, stopping at
      # the first refusal. A `gh` failure is logged, never raised: the round
      # is decided either way, and the label is the decision's echo.
      #
      # @param subject [Plans::Subject]
      # @param labels [Array<Plans::ReviewLabel>]
      # @return [String, nil] why a passing label was refused
      def label(subject, labels)
        return if @review.nil?

        subject.pull_requests.select(&:open?).each do |pull|
          refused = refusal(pull, labels) and return refused
        end
        nil
      rescue Error => e
        UI.log("could not label #{subject.feature.ordinal}: #{e.message}", level: :warn, plan: subject.feature.ordinal.to_s)
        nil
      end

      # Labels the pull request for a decided round. A passing label refused
      # while CI is red or pending turns the round into a rejection: the
      # reviewers judged code CI has not passed.
      #
      # @param subject [Plans::Subject]
      # @param decision [Decision] decided, not pending
      # @return [Decision] the one the pull request now carries
      def conclude(subject, decision)
        refused = label(subject, decision.verdict.labels) or return decision

        label(subject, [Plans::ReviewLabel::REJECTED])
        decision.with(target: :rejected, note: "#{decision.note}; rejected: #{refused}")
      end

      # @param subject [Plans::Subject]
      # @return [void] `review-in-progress` on every open pull request
      def started(subject)
        label(subject, [Plans::ReviewLabel::IN_PROGRESS])
        nil
      end

      private

      # Each reviewer's last verdict in this round, by name.
      #
      # @param subject [Plans::Subject]
      # @return [Hash{String => String}]
      def round(subject)
        data = Plans::PlanState.for(subject.feature.path).read
        moves = data["moves"].to_i
        names = reviewers(subject).map(&:name)
        data["stages"].select { names.include?(it["agent"]) && it["verdict"] && it["review"] == moves }
                      .to_h { [it["agent"], it["verdict"]] }
      end

      # @param notes [Hash{String => String}] every reviewer's note, by name
      # @return [Decision]
      def decided(notes)
        verdict = Plans.verdict(notes.map { |name, said| Plans::Verdict.vote(agent: name, note: said) })
        Decision.new(verdict:, pending: [], target: target(verdict, notes.values), note: "review #{verdict.names.join(" + ")}")
      end

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

      # @param verdict [Plans::Verdict]
      # @param notes [Array<String>]
      # @return [Symbol]
      def target(verdict, notes)
        return :approved if verdict.passing?

        notes.any? { it.match?(SLOP) } ? :slop : :rejected
      end
    end
  end
end

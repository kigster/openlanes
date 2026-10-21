# frozen_string_literal: true

module OpenLanes
  module Engine
    # What a {PrWatch::Outcome} does to the plan folder (M4): the side
    # effects the watch itself refuses to have.
    #
    # A person's verdict arrives on GitHub, not in a ledger, so this is where
    # it is written down: the pull request's row in `pull-requests.md`, the
    # folder's state, and for a rejection the comments, mailed to the agents
    # who fix it. Each step is asked of the folder as it stands, so applying
    # the same outcome twice changes nothing the second time; that is what
    # lets the watch ask GitHub again every 15 seconds without remembering
    # what it already did.
    class PrOutcomes
      # What changed, for the log.
      #
      # @!attribute [r] plan
      #   @return [String] ordinal
      # @!attribute [r] pr
      #   @return [Integer]
      # @!attribute [r] to
      #   @return [Symbol, nil] the state the folder moved to, nil when it stayed
      # @!attribute [r] note
      #   @return [String]
      Applied = Data.define(:plan, :pr, :to, :note)

      # Who signs a mail carrying a person's review comments.
      SENDER = "github"

      # @param tree_dir [String] the `.plans` directory, reread after each rename
      # @param agents [Agents::Registry] who handles 🔴, and so gets the comments
      # @param clock [#call] the time a merge is recorded at
      def initialize(tree_dir:, agents:, clock: -> { Clock::System.now })
        @tree_dir = tree_dir
        @agents = agents
        @clock = clock
      end

      # @param outcome [PrWatch::Outcome]
      # @return [Applied, nil] nil when the folder already said so
      def apply(outcome)
        case outcome.kind
        when :rejected then reject(outcome)
        when :merged then merged(outcome)
        when :closed then closed(outcome)
        end
      end

      private

      # `review-rejected` with comments: 🔴, and the comments to the builders.
      # A plan already at 🔴 has been told; one at 🟢 passes through 👀, the
      # only state the machine rejects from.
      def reject(outcome)
        subject = find(outcome.plan) or return nil
        return nil if subject.status.key == :rejected

        moved = walk(subject, :rejected) or return nil
        # A person overruled the approval: the board must stop showing it
        # as finished.
        Plans::PlanState.for(moved.feature.path).unfinish!
        mailed = mail(moved, outcome)
        Applied.new(plan: outcome.plan,
          pr: outcome.pr,
          to: :rejected,
          note: "PR ##{outcome.pr} labelled #{Plans::ReviewLabel::REJECTED.name}; mailed #{mailed.join(", ")}")
      end

      # Merged on GitHub: the row says so, `state.json` says when (the
      # watch learns of it on the poll after, which is as close as a
      # local clock gets), and once no pull request is left open the plan is
      # ✅, by the person who merged it.
      def merged(outcome)
        subject = find(outcome.plan) or return nil
        record(subject, outcome.pr, "merged")
        Plans::PlanState.for(subject.feature.path).finish!("merged", at: @clock.call)
        subject = find(outcome.plan)
        return applied(outcome, nil, "merged") if subject.pull_requests.any?(&:open?)

        to = walk(subject, :approved) ? :approved : nil
        applied(outcome, to, "merged")
      end

      # Closed unmerged: the row says so, and a plan with nothing merged and
      # nothing open is ❌, with `discarded.md` saying who closed what.
      def closed(outcome)
        subject = find(outcome.plan) or return nil
        record(subject, outcome.pr, "closed")
        subject = find(outcome.plan)
        prs = subject.pull_requests
        return applied(outcome, nil, "closed unmerged") if prs.any? { it.open? || it.merged? }

        return applied(outcome, nil, "closed unmerged") if subject.status.key == :discarded

        note = File.join(subject.feature.path, "discarded.md")
        written = !File.exist?(note) && File.write(note, <<~MARKDOWN)
          # Discarded

          Every pull request was closed on GitHub without merging: #{prs.map { "##{it.number}" }.join(", ")}.
        MARKDOWN
        to = walk(subject, :discarded) ? :discarded : nil
        # ❌ requires the note, so it is written before the move; a refused
        # move takes it back, or the folder would carry a discarded note
        # while claiming some other state.
        File.delete(note) if written && to.nil?
        applied(outcome, to, "closed unmerged")
      end

      # @return [Applied]
      def applied(outcome, to, what) = Applied.new(plan: outcome.plan, pr: outcome.pr, to:, note: "PR ##{outcome.pr} #{what}")

      # Rewrite one row's state in `pull-requests.md`, worded as
      # {Plans::PullRequests::STATES} words it, leaving every other row and
      # every line around the table alone.
      def record(subject, number, word)
        pair = Plans::PullRequests::STATES.find { |pattern, _| pattern.match?(word) } or
          raise(Error, "no pull request state matches #{word.inspect}; Plans::PullRequests::STATES must word it")
        state = pair.last
        rows = subject.pull_requests.map do |pr|
          mine = pr.number.to_s.delete("#").to_i == number
          { number: pr.number, title: pr.title, url: pr.url, state: mine ? state : pr.state }
        end
        Plans::PullRequests.upsert(File.join(subject.feature.path, Plans::PullRequests::FILENAME), rows)
      end

      # Move to +to+, through 👀 when the plan is still at 🟢: a person who
      # ruled on GitHub before hansolo did has reviewed it all the same.
      #
      # @return [Plans::Subject, nil] the plan after the move, nil when the
      #   machine refused it
      def walk(subject, to)
        subject.machine.promote!(:in_review) if subject.status.key == :ready_for_review && !subject.machine.may?(to)
        subject = find(subject.feature.ordinal.to_s)
        return nil unless subject.machine.may?(to)

        subject.machine.promote!(to)
        find(subject.feature.ordinal.to_s)
      rescue Plans::StateMachine::Refused
        nil
      end

      # @return [Array<String>] who was mailed
      def mail(subject, outcome)
        body = ["PR ##{outcome.pr} was labelled #{Plans::ReviewLabel::REJECTED.name} on GitHub.", *comments(outcome)].join("\n\n")
        status = Plans::STATUS_BY_KEY.fetch(:rejected)
        @agents.all.select { it.handles?(status) }.map(&:name).each do |name|
          Plans::Mailbox.new(dir: subject.feature.path).append(from: SENDER, to: name, body:)
        end
      end

      def comments(outcome)
        return ["No comment was left; read the review on GitHub."] if outcome.comments.empty?

        outcome.comments.map { |c| "#{c[:author]} (#{c[:url]}):\n\n#{c[:body].strip}" }
      end

      def find(ordinal) = Plans::Tree.new(dir: @tree_dir).find(ordinal)
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    # What the engine does with a 🏁 Completed plan once palpatine has ruled
    # (decisions P1 to P5).
    #
    # palpatine only writes `plan.md` and signs. Everything that leaves the
    # machine happens here: labelling each `ready-to-merge` pull request
    # `auto-merged` or `merge-manually`, merging the `auto` ones one at a
    # time under `merge.by: auto`, and rebasing the siblings left open onto
    # `main` after each merge. A rebase that raises leaves that sibling for a
    # person, and every other open sibling is still rebased or left in the
    # same pass, rather than retrying the merge on old green CI. A branch
    # GitHub still reports as `BEHIND` is never merged. Every step is asked of
    # GitHub as it stands, so {#advance} may be called on every poll and does
    # nothing twice. That is also how a sibling waits for CI on its rebased
    # head, and how a person's merge of a `merge-manually` pull request is
    # noticed in either mode.
    #
    # The plan reaches ✅ through {PrOutcomes}, once nothing is left open,
    # exactly as when a person merges the last pull request by hand.
    class Merging
      # The phase an agent definition declares to be the risk assessor. Its
      # Completed note carries the verdicts.
      PHASE = "completion"

      # The two verdicts palpatine may give.
      VERDICTS = %w[auto manual].freeze

      # One verdict, with or without the pull request it is for.
      VERDICT = /(auto|manual)(?:\s+#?(\d+))?/i

      # The only notes read at all: `auto`, `manual #13`, `auto #12, manual #13`,
      # with at most one bare verdict, first. Matched against the whole note,
      # because a scan found the `auto` in "do not auto-merge" and would have
      # merged the plan.
      NOTE = /\A\s*#{VERDICT}(?:\s*,\s*(?:auto|manual)\s+#?\d+)*\s*\z/i

      # How long a rebased sibling's zero checks still mean "CI has not
      # registered on the new head yet", as {Verification::Outcome::NO_CHECKS_GRACE}
      # does for the verification commit.
      NO_CHECKS_GRACE = Verification::Outcome::NO_CHECKS_GRACE

      # Who signs the comment carrying a rebase conflict.
      SENDER = "openlanes"

      # What one call did, for the log.
      #
      # @!attribute [r] note
      #   @return [String]
      # @!attribute [r] to
      #   @return [Symbol, nil] the state the folder moved to, nil when it stayed
      # @!attribute [r] merged
      #   @return [Boolean] whether the engine merged a pull request in this pass
      Result = Data.define(:note, :to, :merged) do
        def initialize(to: nil, merged: false, **rest) = super
      end

      class << self
        # The verdict for each pull request, read off palpatine's note. A
        # bare verdict covers every pull request it does not name; a pull
        # request the note says nothing about, or a note that is missing or
        # not in the {NOTE} shape, is `manual` (P4): a wrong `manual` costs a
        # person ten minutes, a wrong `auto` can ship an outage.
        #
        # @param note [String, nil]
        # @param numbers [Array<Integer>] the `ready-to-merge` pull requests
        # @return [Hash{Integer => String}]
        def verdicts(note, numbers)
          return numbers.to_h { [it, "manual"] } unless readable?(note)

          found = note.to_s.scan(VERDICT).map { |word, number| [word.downcase, number&.to_i] }
          named = found.select(&:last).to_h { |word, number| [number, word] }
          bare = found.find { |_, number| number.nil? }&.first || "manual"
          numbers.to_h { |n| [n, named.fetch(n, bare)] }
        end

        # @param note [String, nil]
        # @return [Boolean] whether the note is in the {NOTE} shape
        def readable?(note) = note.to_s.match?(NOTE)
      end

      # @param github [Vcs::GitHub]
      # @param outcomes [PrOutcomes] records merges and rejections, and moves the folder
      # @param merge_by [#call, Symbol] {Config#merger}, read live
      # @param worktree [Vcs::Worktree, nil] where a plan's own branch is checked out
      # @param publisher [Vcs::Publisher, nil] pushes a rebased branch, with the lease
      # @param clock [#call]
      def initialize(github:, outcomes:, merge_by:, worktree: nil, publisher: nil, clock: -> { Clock::System.now })
        @github = github
        @outcomes = outcomes
        @merge_by = merge_by
        @worktree = worktree
        @publisher = publisher
        @clock = clock
      end

      # palpatine signed, or its run ended without a signature: keep the
      # verdicts for this visit to 🏁, then act on them.
      #
      # @param subject [Plans::Subject] at 🏁
      # @param note [String, nil] palpatine's Completed note; nil reads as `manual` throughout
      # @return [Result]
      def assess(subject, note)
        numbers = subject.pull_requests.select(&:open?).map { number_of(it) }
        unless note.nil? || self.class.readable?(note)
          UI.log("palpatine's note is not a verdict list, so every pull request is manual: #{note.inspect}",
            level: :warn,
            plan:  subject.feature.ordinal.to_s)
        end
        Plans::PlanState.for(subject.feature.path).assess!(self.class.verdicts(note, numbers), at: @clock.call)
        advance(subject)
      end

      # @param subject [Plans::Subject]
      # @return [Boolean] whether palpatine has ruled on this visit to 🏁, so
      #   nobody is to start it again
      def assessed?(subject) = subject.status.key == :completed && !record(subject).nil?

      # One pass over a 🏁 plan's pull requests. At most one merge per pass:
      # the siblings are rebased after it, and each must show green CI on
      # its new head before it merges in turn.
      #
      # @param subject [Plans::Subject] at 🏁, assessed
      # @return [Result]
      def advance(subject)
        record = record(subject) or return Result.new(note: "palpatine has not ruled yet")

        notes = []
        subject.pull_requests.select(&:open?).each do |pull|
          step = step(subject, pull, record)
          next unless step

          notes << step.note
          return Result.new(note: notes.join("; "), to: step.to, merged: step.merged) if step.to || step.merged
        end
        Result.new(note: notes.empty? ? "waiting on every pull request" : notes.join("; "))
      end

      private

      # One pull request, one step along its machine.
      #
      # @return [Result, nil] nil when there is nothing to do for it now
      def step(subject, pull, record)
        number = number_of(pull)
        repo = Vcs::GitHub.repo_of(pull.url)
        live = @github.pull_request(pull.url || number.to_s)
        return settled_by_someone(subject, number, live[:state]) unless live[:open]

        machine = Plans::PullRequestMachine.new(pull, live[:labels])
        return nil unless machine.key == :ready_to_merge

        verdict = record.dig("verdicts", number.to_s) || "manual"
        return leave(machine, number, repo, "palpatine said manual") if verdict == "manual"
        return leave(machine, number, repo, "merge.by is #{merge_by}") unless merge_by == :auto

        merge(subject, machine, number, repo, record, live[:head], merge_state: live[:merge_state])
      end

      # Merged or closed on GitHub, by the engine a moment ago or by a person
      # at any time, in either mode.
      #
      # @param state [String] as {Vcs::GitHub.state_label} words it
      # @return [Result]
      def settled_by_someone(subject, number, state)
        kind = state.to_s.match?(/merged/i) ? :merged : :closed
        applied = @outcomes.apply(PrWatch::Outcome.new(plan: subject.feature.ordinal.to_s, pr: number, kind:))
        Result.new(note: "PR ##{number} #{kind}", to: applied&.to)
      end

      # @param comment [Boolean] post +why+ on the pull request, so a person
      #   looking at it sees why the engine stepped away
      # @return [Result]
      def leave(machine, number, repo, why, comment: false)
        machine.fire!(:leave_for_a_person)
        @github.swap_label(number:,
          repo:,
          add: Plans::ReviewLabel::MERGE_MANUALLY,
          remove: Plans::ReviewLabel.displaced_by(Plans::ReviewLabel::MERGE_MANUALLY))
        @github.comment(number:, repo:, body: why) if comment
        Result.new(note: "PR ##{number} #{Plans::ReviewLabel::MERGE_MANUALLY}: #{why}")
      end

      # Merge once CI is green on the head as it stands, then rebase the
      # siblings. A merge GitHub refuses, a conflict among the reasons, is
      # left for a person rather than retried every poll. So is one with no
      # CI at all: nobody watches this merge, and no checks is no evidence.
      # The merge names the head read before the checks, so a push in
      # between makes GitHub refuse it rather than merge a head CI never saw.
      # A branch still behind `main` is the same: CI on that head never saw
      # the commit just merged, so a person rebases it.
      #
      # @param head [String, nil] the head commit, as read before the checks
      # @param merge_state [String, nil] GitHub's `mergeStateStatus`
      # @return [Result, nil]
      def merge(subject, machine, number, repo, record, head, merge_state: nil)
        ci = Vcs::CiGate.verdict(@github.checks(number:, repo:))
        ci = :registering if ci == :none && registering?(record, number)
        return Result.new(note: "PR ##{number} waits on CI before it merges") if %i[pending registering].include?(ci)
        return reject(subject, number, repo, "CI is red on PR ##{number} after its rebase onto main.") if ci == :red
        return leave(machine, number, repo, "no CI checks ran") if ci == :none
        return leave(machine, number, repo, "its head commit could not be read") if head.to_s.empty?
        return leave(machine, number, repo, "its branch is behind main", comment: true) if behind?(merge_state)

        begin
          @github.merge(number:, repo:, head:)
        rescue OpenLanes::Error => e
          return leave(machine, number, repo, e.message)
        end
        machine.fire!(:merge_automatically)
        @github.swap_label(number:,
          repo:,
          add: Plans::ReviewLabel::AUTO_MERGED,
          remove: Plans::ReviewLabel.displaced_by(Plans::ReviewLabel::AUTO_MERGED))
        merged = settled_by_someone(subject, number, "Merged")
        done = Result.new(note: "PR ##{number} #{Plans::ReviewLabel::AUTO_MERGED}", to: merged.to, merged: true)
        return done if merged.to

        rebased = rebase_siblings(fresh(subject), number)
        rebased ? rebased.with(note: "#{done.note}; #{rebased.note}", merged: true) : done
      end

      # Every pull request of the plan still open, onto `main` (P5). The
      # plan's own branch is rebased in its worktree and pushed with the
      # lease; a sibling from any other branch is rebased on GitHub's side.
      # A conflict still sends the plan to 🔴. Anything else that raises
      # (a refused push, a GitHub update that did not finish) leaves that
      # sibling for a person, and the walk continues: returning from the
      # first raise used to skip later siblings, which kept `ready-to-merge`
      # and the old green CI. GitHub's `BEHIND` is silent unless the base
      # requires branches to be up to date, so each sibling must be rebased
      # or left in this pass.
      #
      # @return [Result, nil] the rejection a conflict caused, or the leaves a
      #   rebase that raised caused; nil when every sibling rebased
      def rebase_siblings(subject, merged)
        notes = []
        subject.pull_requests.select(&:open?).each do |pull|
          number = number_of(pull)
          repo = Vcs::GitHub.repo_of(pull.url)
          why = rebase(subject, pull, number, repo)
          return reject(subject, number, repo, why) if why

          Plans::PlanState.for(subject.feature.path).rebased!(number, at: @clock.call)
        rescue OpenLanes::Error => e
          UI.log("rebase after merging ##{merged} not finished: #{e.message}",
            level: :warn,
            plan:  subject.feature.ordinal.to_s)
          notes << leave_unrebased(pull, number, repo, e.message).note
        end
        notes.empty? ? nil : Result.new(note: notes.join("; "))
      end

      # @return [Result]
      def leave_unrebased(pull, number, repo, error)
        live = @github.pull_request(pull.url || number.to_s)
        machine = Plans::PullRequestMachine.new(pull, live[:labels])
        leave(machine, number, repo, "rebase onto main failed: #{error}", comment: true)
      end

      # @param status [String, nil] GitHub's `mergeStateStatus`
      # @return [Boolean]
      def behind?(status) = status.to_s.upcase == "BEHIND"

      # @return [String, nil] why the rebase failed, nil when it went through
      def rebase(subject, pull, number, repo)
        checkout = own_checkout(subject, pull) or return github_rebase(number, repo)

        refresh = Vcs::Refresh.new(path: checkout.path)
        outcome = refresh.call
        if outcome.conflicted?
          refresh.abort!("conflicts after a sibling merged")
          return "PR ##{number} no longer rebases onto #{outcome.base}: conflicts in #{outcome.files.join(", ")}."
        end
        # Skipped or refused locally (a dirty tree, no remote): GitHub can
        # still rebase the branch it holds, and says so if it conflicts.
        return github_rebase(number, repo) unless outcome.done?

        @publisher.pushed!(checkout, "HEAD") unless outcome.kind == :current
        nil
      end

      # The plan's own checkout, when it already exists and builds this
      # pull request. Never made here: a poll that minted a worktree per
      # 🏁 plan would leave one behind for every plan a person merges.
      #
      # @return [Vcs::Worktree::Checkout, nil]
      def own_checkout(subject, pull)
        return nil if @worktree.nil? || @publisher.nil? || !File.directory?(@worktree.path_for(subject.feature))

        checkout = @worktree.checkout_for(subject.feature)
        @publisher.branch_mismatch(pull, checkout) ? nil : checkout
      end

      # @return [String, nil]
      def github_rebase(number, repo)
        @github.update_branch(number:, repo:)
        nil
      rescue OpenLanes::Error => e
        "PR ##{number} no longer rebases onto main: #{e.message}"
      end

      # A conflict or red CI after a rebase: `review-rejected` on the pull
      # request, and the plan to 🔴 with the reason mailed to luke and rey,
      # through {PrOutcomes} exactly as a person's rejection is.
      #
      # @return [Result]
      def reject(subject, number, repo, why)
        @github.swap_label(number:,
          repo:,
          add: Plans::ReviewLabel::REJECTED,
          remove: Plans::ReviewLabel.displaced_by(Plans::ReviewLabel::REJECTED))
        @github.comment(number:, repo:, body: why)
        comments = [{ author: SENDER, url: "", body: why }]
        applied = @outcomes.apply(PrWatch::Outcome.new(plan: subject.feature.ordinal.to_s, pr: number, kind: :rejected, comments:))
        Result.new(note: "PR ##{number} back to the builders: #{why}", to: applied&.to)
      end

      # Whether a rebased sibling's push is recent enough that CI may not
      # have registered on its new head yet.
      #
      # @return [Boolean]
      def registering?(record, number)
        at = record.dig("rebased", number.to_s) or return false

        @clock.call - Time.iso8601(at) < NO_CHECKS_GRACE
      end

      # @return [Hash, nil]
      def record(subject) = Plans::PlanState.for(subject.feature.path).merge_risk

      # @return [Symbol]
      def merge_by = @merge_by.respond_to?(:call) ? @merge_by.call : @merge_by

      # @return [Integer]
      def number_of(pull) = Vcs::GitHub.number_of(pull.url || pull.number.to_s)

      # @return [Plans::Subject]
      def fresh(subject) = Plans::Tree.new(dir: File.dirname(subject.feature.path)).find(subject.feature.ordinal.to_s) || subject
    end
  end
end

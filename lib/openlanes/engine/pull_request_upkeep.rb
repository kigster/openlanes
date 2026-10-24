# frozen_string_literal: true

module OpenLanes
  module Engine
    # Keeps open pull requests from going stale while nobody is working on
    # them (decisions U1 to U4).
    #
    # Two duties, both the harness's, since agents may neither push nor
    # label:
    #
    # - {#address}: a `review-rejected` pull request whose head was
    #   committed after the rejection has had its fixes pushed, by the
    #   publisher or by anyone else, so it becomes `review-addressed`. Left
    #   alone, the stale rejection read to the PR watch as a fresh one, and
    #   a fixed pull request sat rejected for good (#93, #83, #44).
    # - {#sweep}: whenever `main` moves, the pull requests waiting to merge
    #   ({Plans::ReviewLabel::WAITING}) are asked whether they still merge
    #   clean. `BEHIND` is updated on GitHub; `DIRTY` is labelled `conflicts`
    #   and handed back as a {Conflict} for bb8-resolver; one that merges
    #   clean again while labelled `conflicts` becomes `conflicts-resolved`.
    #
    # Every answer is read off GitHub as it stands, so either may be called
    # on every poll. What this keeps between polls is only which pull
    # requests still owe an answer: GitHub says `UNKNOWN` for a while after
    # `main` moves.
    class PullRequestUpkeep
      # The branch every plan's pull requests target.
      MAIN = "main"

      # One pull request that no longer merges clean onto `main`.
      #
      # @!attribute [r] ordinal
      #   @return [String] its plan
      # @!attribute [r] number
      #   @return [Integer]
      # @!attribute [r] url
      #   @return [String]
      Conflict = Data.define(:ordinal, :number, :url)

      # What one {#sweep} found.
      #
      # @!attribute [r] conflicts
      #   @return [Array<Conflict>] to be resolved
      # @!attribute [r] notes
      #   @return [Array<String>] one line per pull request acted on, for the log
      Sweep = Data.define(:conflicts, :notes)

      # @param github [Vcs::GitHub]
      # @param clock [#call]
      def initialize(github:, clock: -> { Clock::System.now })
        @github = github
        @clock = clock
        @main = nil
        @owed = Set.new
        @tried = Set.new
      end

      # Swap `review-rejected` for `review-addressed` on every open pull
      # request whose fixes arrived after it was rejected (U1).
      #
      # @return [Array<String>] one line per pull request relabelled or not readable
      def address
        rejected = Plans::ReviewLabel::REJECTED.name
        @github.open_pulls_labelled(rejected).filter_map do |number, _labels|
          address_one(number, rejected)
        rescue OpenLanes::Error => e
          "PR ##{number} not checked for fixes: #{e.message.lines.first.to_s.strip}"
        end
      end

      # Ask the waiting pull requests whether they still merge clean, if
      # `main` moved since the last sweep or any of them still owes an
      # answer (U2, U4).
      #
      # @param subjects [Array<Plans::Subject>] the plans in scope
      # @param busy [Array<String>] ordinals an agent is working in; asked later
      # @return [Sweep]
      def sweep(subjects, busy: [])
        moved!(subjects)
        conflicts = []
        notes = []
        by_ordinal = subjects.to_h { [it.feature.ordinal.to_s, it] }
        @owed.to_a.each do |ordinal, url|
          next if busy.include?(ordinal)

          subject = by_ordinal[ordinal]
          next @owed.delete([ordinal, url]) if subject.nil?

          verdict = check(subject, url)
          @owed.delete([ordinal, url]) unless verdict == :unknown
          case verdict
          when Conflict then conflicts << verdict
          when String then notes << verdict
          end
        rescue OpenLanes::Error => e
          notes << "#{ordinal}: #{url} not checked against #{MAIN}: #{e.message.lines.first.to_s.strip}"
        end
        Sweep.new(conflicts:, notes:)
      end

      # Ask about one pull request again on the next sweep: a resolution was
      # pushed, and only GitHub can say whether it now merges clean.
      #
      # @param conflict [Conflict]
      # @return [void]
      def recheck(conflict) = @owed << [conflict.ordinal, conflict.url]

      # Whether a clean rebase of this pull request's branch may be pushed
      # now: once per head of `main`.
      #
      # @param conflict [Conflict]
      # @return [Boolean]
      def attempt?(conflict) = !@tried.add?([conflict.url, @main]).nil?

      private

      # @return [String, nil]
      def address_one(number, rejected)
        at = @github.labelled_at(number:, name: rejected) or return nil
        head = @github.head_committed_at(number:) or return nil
        return nil unless head > at

        @github.swap_label(number:,
          add: Plans::ReviewLabel::ADDRESSED,
          remove: Plans::ReviewLabel.displaced_by(Plans::ReviewLabel::ADDRESSED))
        "PR ##{number} #{Plans::ReviewLabel::ADDRESSED}: committed #{head.iso8601}, after the rejection at #{at.iso8601}"
      end

      # `main` moved: every open pull request of every plan owes an answer.
      # Which of them are waiting is only known once each is read.
      #
      # @return [void]
      def moved!(subjects)
        head = @github.branch_head(branch: MAIN)
        return if head == @main

        @main = head
        subjects.each do |subject|
          next if subject.status.terminal?

          subject.pull_requests.select(&:open?).each { |pull| @owed << [subject.feature.ordinal.to_s, pull.url.to_s] }
        end
      end

      # @return [Conflict, String, Symbol, nil] a conflict to resolve, a line
      #   for the log, `:unknown` when GitHub has not decided yet, or nil
      def check(subject, url)
        live = @github.pull_request(url)
        return nil unless live[:open]

        labels = live[:labels]
        conflicted = labels.include?(Plans::ReviewLabel::CONFLICTS.name)
        return nil unless conflicted || Plans::ReviewLabel::WAITING.any? { labels.include?(it.name) }

        ordinal = subject.feature.ordinal.to_s
        number = live[:number]
        case live[:merge_state].to_s.upcase
        when "UNKNOWN" then :unknown
        when "DIRTY" then conflict(ordinal, number, url, conflicted)
        when "BEHIND" then update(subject, number)
        else resolved(number) if conflicted
        end
      end

      # @return [Conflict]
      def conflict(ordinal, number, url, labelled)
        unless labelled
          @github.swap_label(number:, add: Plans::ReviewLabel::CONFLICTS, remove: [Plans::ReviewLabel::CONFLICTS_RESOLVED.name])
          @github.comment(number:,
            body: "No longer merges clean onto `#{MAIN}`. Labelled `#{Plans::ReviewLabel::CONFLICTS}`; " \
                  "bb8-resolver rebases it, and the review verdict stays.")
        end
        Conflict.new(ordinal:, number:, url:)
      end

      # Behind `main` without a conflict: GitHub rebases it, and the merge
      # waits for CI on the new head.
      #
      # @return [String]
      def update(subject, number)
        @github.update_branch(number:)
        Plans::PlanState.for(subject.feature.path).rebased!(number, at: @clock.call)
        "PR ##{number} was behind #{MAIN}; rebased on GitHub"
      end

      # @return [String]
      def resolved(number)
        @github.swap_label(number:,
          add: Plans::ReviewLabel::CONFLICTS_RESOLVED,
          remove: [Plans::ReviewLabel::CONFLICTS.name])
        "PR ##{number} merges clean onto #{MAIN} again: #{Plans::ReviewLabel::CONFLICTS_RESOLVED}"
      end
    end
  end
end

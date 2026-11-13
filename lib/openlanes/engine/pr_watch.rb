# frozen_string_literal: true

module OpenLanes
  module Engine
    # In every merge mode (M4, #171): while a person may review, merge or
    # close it, the engine watches each plan's open pull request and says
    # what happened to it.
    #
    # Paced by elapsed time rather than by ticks, so a faster tick loop does
    # not become a faster stream of `gh` calls. It only reads; the dispatcher
    # fires the events and sends the mail.
    class PrWatch
      # What one pull request turned out to be.
      #   :rejected — carries `review-rejected`; `comments` are what to fix
      #   :merged, :closed — no longer open, merged or not
      #   :waiting — still open, waiting on a person
      #   `to` is where a :rejected one sends the plan: 🔴, or 🟡 for a
      #   send-back under `desired_codebase_quality: standard` (plan 035)
      Outcome = Data.define(:plan, :pr, :kind, :comments, :to) do
        def initialize(comments: [], to: :rejected, **rest) = super
      end

      # @param github [Vcs::GitHub]
      # @param clock [#call] monotonic seconds
      # @param interval [Numeric] seconds between polls
      # @param snapshot [#call, nil] `-> Vcs::PullSnapshot`, the open pull
      #   requests; nil lists them with `gh pr list --state all` instead
      def initialize(github:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, interval: 15, snapshot: nil)
        @github = github
        @snapshot = snapshot
        @clock = clock
        @interval = interval
        @last = nil
      end

      # @return [#call, nil] the snapshot this watch reads, shared with the
      #   tick's other readers
      attr_reader :snapshot

      # @return [Boolean] whether a poll is due; the first one waits a full interval
      def due?
        now = @clock.call
        @last ||= now
        now - @last >= @interval
      end

      # One snapshot of the open pull requests (or one `gh pr list`) for
      # every watched plan, and one `gh pr view` for each watched pull
      # request it left out: with a snapshot, only one that has just merged
      # or closed.
      #
      # @param subjects [Array<Plans::Subject>]
      # @return [Array<Outcome>] one per open pull request a plan records
      def poll(subjects)
        @last = @clock.call
        watched = subjects.flat_map { |s| s.pull_requests.select(&:open?).map { |pr| [s, pr.number.to_s.delete("#").to_i] } }
        return [] if watched.empty?

        by_number = rows.to_h { |row| [row[:number], row] }
        watched.filter_map do |subject, number|
          row = by_number[number] || lookup(number) or next
          outcome(subject, number, row)
        end
      end

      private

      # @return [Array<Hash>] rows shaped like {Vcs::GitHub#pulls}
      def rows = @snapshot ? @snapshot.call.pulls : @github.pulls(state: "all")

      # `gh pr list` returns only the newest pull requests, up to its limit,
      # so a plan whose pull request is older than that would drop out of
      # every poll and its merge or rejection would never be applied. Asked
      # by number instead. One that cannot be read is skipped this poll and
      # asked again on the next, rather than stopping the watch for all.
      #
      # @return [Hash, nil] a row shaped like {Vcs::GitHub#pulls}
      def lookup(number)
        @github.pull_request(number.to_s)
      rescue Error
        nil
      end

      def outcome(subject, number, row)
        plan = subject.feature.ordinal.to_s
        if row[:open]
          return Outcome.new(plan:, pr: number, kind: :waiting) unless rejected?(row)

          Outcome.new(plan:, pr: number, kind: :rejected, comments: @github.review_comments(number:))
        else
          Outcome.new(plan:, pr: number, kind: row[:state].to_s.start_with?("Merged") ? :merged : :closed)
        end
      end

      def rejected?(row) = Array(row[:labels]).include?(Plans::ReviewLabel::REJECTED.name)
    end
  end
end

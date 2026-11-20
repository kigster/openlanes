# frozen_string_literal: true

require "digest"
require "open3"

module OpenLanes
  module Web
    # What the Worktrees page draws: every checkout of the repository but the
    # main one, each with its branch, its plan and that plan's state, and
    # what `git status` says of it. The diff and the pull requests are asked
    # for one worktree at a time, since the page opens one panel at a time
    # and a pull request's CI is a `gh` call each.
    class Worktrees
      # An id that names no worktree on disk now.
      class NotFound < Error; end

      # A plan branch, `<user>/<ordinal>-<slug>`, as {Vcs::Worktree#branch_for} names them.
      PLAN_BRANCH = %r{\A[^/]+/(?<ordinal>\d{3}\.\d{2})-}

      # `gh pr checks` buckets, worst first: one red check makes the square red.
      CI = [%w[fail fail], %w[cancel fail], %w[pending pending]].freeze

      # @param root [String] the main checkout
      # @param plans_dir [String]
      # @param repo [String, nil] "github.com/owner/name", for the compare link
      # @param github [#checks] the `gh` seam
      # @param diff [OpenLanes::Web::BranchDiff]
      # @param working [#call] plan ordinal to whether an agent works it now
      def initialize(root:, plans_dir:, repo: nil, github: nil, diff: nil, working: ->(_) { false }) # rubocop:disable Metrics/ParameterLists
        @root = root
        @plans_dir = plans_dir
        @repo = repo
        @github = github
        @diff = diff || BranchDiff.new(root:)
        @working = working
      end

      # The plans are read once for the whole list, not once per worktree.
      #
      # @return [Array<Hash>] `{ id:, path:, branch:, plan:, modified:, lines: }`, in git's order
      def list
        tree = Plans.tree(@plans_dir)
        entries.map { |e| e.merge(plan: plan_of(e[:branch], tree), modified: status_of(e[:path]), lines: lines_of(e[:path])) }
      end

      # @param id [String]
      # @return [Hash] `{ stat:, patch:, truncated:, base:, compare_url: }`
      # @raise [NotFound]
      def diff(id)
        branch = entry(id)[:branch]
        return BranchDiff::EMPTY.merge(base: @diff.base, compare_url: nil) if branch.empty?

        @diff.for_branch(branch).merge(base: @diff.base, compare_url: compare_url(branch))
      end

      # The plan's pull requests, as `pull-requests.md` lists them, each with
      # its CI as one word: pass, fail, pending, none, or unknown when `gh`
      # could not say.
      #
      # @param id [String]
      # @return [Array<Hash>] `{ number:, title:, url:, state:, ci: }`
      # @raise [NotFound]
      def pulls(id)
        subject = subject_of(entry(id)[:branch]) or return []
        subject.pull_requests.map do |pr|
          { number: pr.number&.to_i, title: pr.title, url: pr.url, state: pr.state, ci: pr.number ? ci_of(pr.number.to_i) : "none" }
        end
      end

      # @param path [String]
      # @return [String] the id the page and the routes name a worktree by: no path ever travels in a URL
      def self.id_for(path) = Digest::SHA256.hexdigest(path)[0, 12]

      private

      # @return [Array<Hash>] `{ id:, path:, branch: }`, the main checkout left out
      def entries
        blocks = git("worktree", "list", "--porcelain").to_s.split(/\n{2,}/)
        main = canonical(@root)
        blocks.filter_map do |block|
          lines = block.lines(chomp: true)
          path = lines.find { it.start_with?("worktree ") }&.delete_prefix("worktree ") or next
          next if canonical(path) == main

          branch = lines.find { it.start_with?("branch ") }.to_s.delete_prefix("branch ").delete_prefix("refs/heads/")
          { id: self.class.id_for(path), path:, branch: }
        end
      end

      # @raise [NotFound]
      def entry(id) = entries.find { it[:id] == id } || raise(NotFound, "there is no worktree #{id}")

      # @param tree [OpenLanes::Plans::Tree] one already read, when the caller has it
      # @return [OpenLanes::Plans::Subject, nil]
      def subject_of(branch, tree = Plans.tree(@plans_dir))
        match = PLAN_BRANCH.match(branch) or return nil
        tree.find(match[:ordinal])
      end

      # @return [Hash, nil]
      def plan_of(branch, tree)
        subject = subject_of(branch, tree) or return nil
        feature = subject.feature
        ordinal = feature.ordinal.to_s
        { ordinal:, title: feature.title, status: feature.status.key.to_s, label: feature.status.label,
          emoji: feature.status.emoji, working: @working.call(ordinal) ? true : false }
      end

      # @return [Array<String>] `git status --short` lines; empty for a clean or vanished checkout
      def status_of(path) = git_in(path, "status", "--short").to_s.lines(chomp: true)

      # Lines added and removed against the default branch, counted from the
      # files on disk rather than the branch tip, so work not yet committed
      # counts. New files git does not track yet are not counted.
      #
      # @return [Hash] `{ added:, removed: }`
      def lines_of(path)
        fork = git_in(path, "merge-base", @diff.base, "HEAD").to_s.strip
        return { added: 0, removed: 0 } if fork.empty?

        counts = git_in(path, "diff", "--no-ext-diff", "--numstat", fork).to_s.lines.map { it.split("\t", 3).first(2) }
        # A binary file counts "-": no lines either way.
        { added: counts.sum { it[0].to_i }, removed: counts.sum { it[1].to_i } }
      end

      # @return [String]
      def ci_of(number)
        buckets = @github ? @github.checks(number:).map { it[:bucket] } : []
        return "none" if buckets.empty?

        CI.each { |bucket, word| return word if buckets.include?(bucket) }
        "pass"
      rescue OpenLanes::Error
        "unknown"
      end

      # @return [String, nil]
      def compare_url(branch)
        host_path = @repo.to_s.sub(%r{\Ahttps?://}, "").delete_suffix(".git")
        return nil unless host_path.start_with?("github.com/")

        "https://#{host_path}/compare/#{@diff.base}...#{branch}"
      end

      def canonical(path)
        File.realpath(path)
      rescue SystemCallError
        path
      end

      def git(*) = git_in(@root, *)

      # @return [String, nil] STDOUT, nil when git failed
      def git_in(dir, *)
        out, status = Open3.capture2("git", "-C", dir, *, err: File::NULL)
        out if status.success?
      end
    end
  end
end

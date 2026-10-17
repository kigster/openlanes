# frozen_string_literal: true

require "fileutils"
require "open3"
require "tempfile"
require "tty/command"

module OpenLanes
  module Vcs
    # Turns a finished worktree into a pushed branch and a pull request.
    #
    # This is the one place the harness reaches off the machine, so it does
    # nothing under `--dry-run`, is skipped with `--no-git-push`, and refuses anything
    # it is not certain about. Everything it does is reported before it does it.
    #
    # Titles follow the convention the whole system joins on:
    #
    #     [002.00](A) Tenancy Households       — a plan's first pull request
    #     [002.00](B) Tenancy Households       — its second
    #
    # The slug is title-cased from the folder name, so the title reads as a
    # sentence rather than as a path fragment.
    class Publisher
      # A published, or publishable, pull request.
      #
      # @!attribute [r] ordinal
      #   @return [OpenLanes::Plans::Ordinal]
      # @!attribute [r] branch
      #   @return [String]
      # @!attribute [r] title
      #   @return [String]
      # @!attribute [r] url
      #   @return [String, nil] nil on a dry run or a refusal
      # @!attribute [r] refusal
      #   @return [String, nil]
      # @!attribute [r] updated
      #   @return [Boolean] whether the push went to a pull request the plan
      #     already had open, rather than opening a new one
      # @!attribute [r] label_error
      #   @return [String, nil] why `ready-for-review` could not be applied; the
      #     pull request stays open regardless (open question 4)
      Publication = Data.define(:ordinal, :branch, :title, :url, :refusal, :updated, :label_error) do
        def initialize(updated: false, label_error: nil, **rest) = super

        # @return [Boolean]
        def published? = !url.nil?
      end

      # A..Z, which is more parts than any feature should be split into.
      LETTERS = ("A".."Z").to_a.freeze

      # @param root [String] repository the worktree belongs to
      # @param command [TTY::Command]
      # @param base [String] the branch pull requests target
      # @param dry_run [Boolean]
      # @param github [OpenLanes::Vcs::GitHub] asked which branch an open pull
      #   request is built from
      def initialize(root:, command: TTY::Command.new(printer: :null), base: "main", dry_run: true, github: GitHub.new)
        @root = root
        @command = command
        @github = github
        @base = base
        @dry_run = dry_run
      end

      # Push one plan's branch and open its pull request, or, when the plan
      # already has one open, push to it.
      #
      # A re-build after 🔴 Changes Requested is the second case. Its branch
      # already carries the open pull request the reviewer asked changes of,
      # and `gh pr create` on that branch fails ("a pull request for branch
      # ... already exists") after the push has gone through, so the fixes
      # reached the pull request and the run reported a refusal. One branch per
      # plan means at most one open pull request per plan, so the open row in
      # `pull-requests.md` is the one to push to.
      #
      # Only if that pull request is built from this checkout's branch, though.
      # `pull-requests.md` does not record the head branch, and an adopted or
      # hand-opened pull request can come from any branch at all; pushing the
      # worktree branch then reaches no pull request while reporting one as
      # updated. So the head is asked of GitHub first, and anything other than
      # the checkout's own branch, or no answer, is a refusal.
      #
      # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
      # @param subject [OpenLanes::Plans::Subject]
      # @param letter [String, nil] force a part letter; nil auto-assigns
      # @return [OpenLanes::Vcs::Publisher::Publication]
      def publish(checkout:, subject:, letter: nil)
        open = subject.pull_requests.select(&:open?).last
        title = open&.title || title_for(subject, letter)

        unless checkout.dirty?
          return refuse(subject, checkout, title, "nothing to publish — the worktree is unchanged")
        end

        untestable = open.nil? && missing_how_to_test(subject)
        return refuse(subject, checkout, title, untestable) if untestable

        return Publication.new(**base_fields(subject, checkout, title), url: nil, refusal: nil) if @dry_run

        mismatch = open && head_mismatch(open, checkout)
        return refuse(subject, checkout, title, mismatch) if mismatch

        carry_plan(checkout, subject)
        commit(checkout, title)
        push(checkout)
        url = open ? open.url : create_pull_request(checkout, subject, title)
        label_error = url.nil? ? nil : label_for_review(url, resubmitted: !open.nil?)

        Publication.new(**base_fields(subject, checkout, title), url:, refusal: nil, updated: !open.nil?, label_error:)
      rescue TTY::Command::ExitError => e
        refuse(subject, checkout, title, git_complaint(e))
      end

      # git and gh put the useful sentence in stderr, several lines below the
      # command they echo. Reporting only the first line reports "it failed".
      #
      # @param error [TTY::Command::ExitError]
      # @return [String]
      def git_complaint(error)
        lines = error.message.lines.map(&:strip).reject(&:empty?)
        stderr = lines.find { |l| l.start_with?("stderr:") }
        complaint = stderr&.delete_prefix("stderr:")&.strip

        complaint.to_s.empty? || complaint == "Nothing written" ? lines.first.to_s : complaint
      end

      # The title a plan's next pull request should carry.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param letter [String, nil]
      # @return [String]
      def title_for(subject, letter = nil)
        "[#{subject.feature.ordinal}](#{letter || auto_letter(subject)}) #{subject.feature.title}"
      end

      # Which part this is. Always a letter, starting at A: a plan that turns out
      # to need only one pull request still reads consistently with every other,
      # and nothing has to be renamed when a second arrives.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def auto_letter(subject) = LETTERS.fetch(subject.pull_requests.size, LETTERS.last)

      # Left out of the copy: the half-written temporaries an atomic write
      # renames into place (`state.json.<pid>.<thread>.tmp`).
      CARRY_EXCLUDED = ["*.tmp"].freeze

      # Copy the plan's folder from the main checkout into the worktree, so
      # the pull request carries its spec, plan and state next to the code.
      #
      # The main checkout stays the only writer. The engine reads, signs and
      # renames the plan there and nowhere else; the worktree gets a snapshot,
      # refreshed on every publish. Every copy of the same plan number is
      # removed first, so a folder renamed since the last publish (⭐ to 🟢,
      # say) does not leave its old name behind in the branch, and a file
      # deleted in the main checkout is deleted in the branch too.
      #
      # Nothing is copied when the worktree is the main checkout itself, which
      # would delete the source, or when the plans live outside the
      # repository, where the branch has no place for them.
      #
      # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
      # @param subject [OpenLanes::Plans::Subject] the plan in the main checkout
      # @return [String, nil] the copy's path, nil when nothing was copied
      def carry_plan(checkout, subject)
        root = real(@root)
        source = real(subject.feature.path)
        return nil if real(checkout.path) == root || !source.start_with?("#{root}/")

        parent = File.join(checkout.path, File.dirname(source.delete_prefix("#{root}/")))
        FileUtils.mkdir_p(parent)
        Dir.children(parent).each do |name|
          next unless Plans::Ordinal.from_dirname(name) == subject.feature.ordinal

          FileUtils.rm_rf(File.join(parent, name))
        end
        copy_tree(source, File.join(parent, File.basename(source)))
      end

      private

      # @param path [String]
      # @return [String] symlinks resolved, so /var and /private/var compare equal
      def real(path)
        File.realpath(path)
      rescue Errno::ENOENT
        File.expand_path(path)
      end

      # @param source [String]
      # @param target [String]
      # @return [String] target
      def copy_tree(source, target)
        Dir.glob("**/*", File::FNM_DOTMATCH, base: source).each do |relative|
          next if relative == "." || CARRY_EXCLUDED.any? { File.fnmatch?(it, File.basename(relative)) }

          from = File.join(source, relative)
          to = File.join(target, relative)
          FileUtils.mkdir_p(File.directory?(from) ? to : File.dirname(to))
          FileUtils.cp(from, to) if File.file?(from)
        end
        FileUtils.mkdir_p(target)
        target
      end

      # Why the open pull request cannot receive this checkout's push, if it
      # cannot.
      #
      # @param open [OpenLanes::Plans::PullRequest]
      # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
      # @return [String, nil] nil when the pull request is built from the checkout's branch
      def head_mismatch(open, checkout)
        head = @github.pull_request(open.number || open.url).fetch(:branch)
        return if head == checkout.branch

        "publish refused — ##{open.number} is built from #{head.empty? ? "an unknown branch" : head}, " \
          "not #{checkout.branch}, so a push would not reach it"
      rescue Error => e
        "publish refused — could not tell which branch ##{open.number} is built from: #{e.message}"
      end

      # @return [Hash]
      def base_fields(subject, checkout, title)
        { ordinal: subject.feature.ordinal, branch: checkout.branch, title: }
      end

      # @return [OpenLanes::Vcs::Publisher::Publication]
      def refuse(subject, checkout, title, why)
        Publication.new(**base_fields(subject, checkout, title), url: nil, refusal: why)
      end

      # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
      # @param title [String]
      # @return [void]
      def commit(checkout, title)
        run(checkout, "git", "add", "-A")
        # The subject line drops the bracketed prefix: it belongs in the pull
        # request title, where things join on it, not in every commit message.
        run(checkout, "git", "commit", "-m", title.sub(/\A\[[^\]]+\](?:\([A-Z]\))?\s*/, ""))
      end

      # The branch is the checkout's own, named by {Worktree#branch_for} and
      # written only by this harness, so after the harness has rebased it
      # (see {Refresh}) it may replace what `origin` holds. The lease alone
      # is not enough: it trusts the tracking ref, and worktrees share
      # `refs/remotes` with the main checkout, so a fetch there (an editor's
      # auto-fetch, `gh pr checkout`) moves it onto somebody else's push and
      # the lease would then let us overwrite it. `--force-if-includes` adds
      # that the tracking ref's tip must be in this branch's own reflog,
      # i.e. a commit the harness had here. It is a no-op beside an explicit
      # `:<expect>`, so the lease names only the ref. A branch with no
      # tracking ref yet gets a plain push, which can only fast-forward.
      #
      # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
      # @return [void]
      def push(checkout)
        # Declared first, so an agent still running in another worktree is
        # not blamed for the tracking ref this push moves under it.
        Execution::Boundary.sanction(checkout.path, "origin", checkout.branch)
        run(checkout, "git", "push", *lease(checkout), "-u", "origin", checkout.branch)
      end

      # @param checkout [OpenLanes::Vcs::Worktree::Checkout]
      # @return [Array<String>] the lease flags, or nothing
      def lease(checkout)
        # Read directly rather than through {#run}: it is a local lookup that
        # changes nothing, and the command seam is for what leaves the machine.
        seen, = Open3.capture2("git",
          "-C",
          checkout.path,
          "rev-parse",
          "--verify",
          "--quiet",
          "refs/remotes/origin/#{checkout.branch}",
          err: File::NULL)
        seen.strip.empty? ? [] : ["--force-with-lease=refs/heads/#{checkout.branch}", "--force-if-includes"]
      end

      # @return [String, nil] the pull request URL
      def create_pull_request(checkout, subject, title)
        Tempfile.create(["pr", ".md"]) do |file|
          file.write(description(subject, title))
          file.flush
          result = run(checkout, "gh", "pr", "create", "-a", "@me", "-B", @base, "-t", title, "-F", file.path)
          return result.out.to_s[%r{https://\S+}]
        end
      end

      # The body `/create-pr` would have written: a title line, a summary lifted
      # from the specification, and a link back to the plan folder so a reviewer
      # can find the rest.
      #
      # @return [String]
      def description(subject, title)
        <<~MARKDOWN
          # #{title}

          ## Summary

          #{summary_text(subject)}

          ## Plan

          Implements `#{subject.feature.dirname}`. The specification and the plan
          for this work live in that folder.

          #{Lifecycle::Completion::HOW_TO_TEST}

          #{how_to_test(subject)}
        MARKDOWN
      end

      # A pull request a person cannot test is not ready for one to review.
      #
      # @return [String, nil] the refusal, or nil when plan.md has the section
      def missing_how_to_test(subject)
        return nil unless how_to_test(subject).empty?

        "publish refused — plan.md has no `#{Lifecycle::Completion::HOW_TO_TEST}` section"
      end

      # A plan.md written before the rename says `## How to verify`; the
      # harness no longer appends a duplicate to it, so its steps are read
      # here under either heading rather than refused.
      #
      # @return [String] the section's body, without its heading
      def how_to_test(subject)
        headings = [Lifecycle::Completion::HOW_TO_TEST, Lifecycle::Completion::FORMER_HOW_TO_TEST]
        lines = subject.read("plan.md").to_s.lines
        start = lines.index { |l| headings.any? { l.strip.casecmp?(it) } } or return ""
        lines[(start + 1)..].take_while { |l| !l.start_with?("## ", "# ") }.join.strip
      end

      # Put `ready-for-review` on the pull request. A resubmission also takes
      # off whatever verdict the last review left: a `review-rejected` still
      # there after the fixes are pushed reads to the watch as a fresh
      # rejection, and the 🟢 plan would be sent straight back to 🔴.
      #
      # @param url [String]
      # @param resubmitted [Boolean] whether the pull request was already open
      # @return [String, nil] the error, when labelling failed
      def label_for_review(url, resubmitted: false)
        number = GitHub.number_of(url)
        remove = resubmitted ? Plans::ReviewLabel.known : []
        @github.swap_label(number:, repo: GitHub.repo_of(url), add: Plans::ReviewLabel::INITIAL, remove:)
        nil
      rescue Error => e
        e.message
      end

      # The specification's own Goal section, verbatim. A pull request body that
      # paraphrases the spec is a second copy that drifts; quoting it is not.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def summary_text(subject)
        text = subject.goal.join("\n\n")
        text.empty? ? "See `#{subject.feature.dirname}/spec.md`." : text
      end

      # @return [TTY::Command::Result]
      def run(checkout, *argv) = @command.run(*argv, chdir: checkout.path)
    end
  end
end

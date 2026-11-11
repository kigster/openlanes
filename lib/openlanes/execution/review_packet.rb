# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"

module OpenLanes
  module Execution
    # What every reviewer of one review round reads before its own
    # instructions: the plan's documents and the pull request's diff, fetched
    # by the harness once (plan 060.00, item 1).
    #
    # Three reviewers used to open the same four files and run `gh pr diff`
    # each, three sets of tool round-trips inside a 300 second clock. Built
    # here, the text is also the same bytes for all three, so it goes first
    # in the prompt, where reviewers on one model share it as a cached
    # prefix.
    #
    # A round is named as {Engine::Reviews} names it, by the plan's `moves`:
    # the first reviewer's start moves the folder to 👀 before any prompt is
    # built, and every way out of review moves it again. The packet is kept
    # on disk under that name, so a reviewer started a tick later, replaced
    # after a failure, or started by a restarted engine reads what the first
    # one read, even though reviewers write `pull-requests.md` meanwhile.
    class ReviewPacket
      # Outside the repository, for the reason {Executor::TRACE_DIR} is: the
      # after-check should have nothing extra to learn to ignore.
      DIR = File.join(Dir.tmpdir, "openlanes-packets")

      # Most characters of diff one packet carries, over all the plan's pull
      # requests: about 30k tokens, paid once by each reviewer. Past it the
      # packet names the files it left out, and the reviewer fetches those.
      DIFF_LIMIT = 120_000

      # Most characters of any one document. A spec or a plan is far below
      # it; a `pull-requests.md` grown over many rounds may not be.
      DOCUMENT_LIMIT = 20_000

      # The documents a reviewer was told to open, in reading order. A folder
      # planned before plan 003 has `implementation-plan.md` for a contract.
      DOCUMENTS = %w[spec.md plan.md contract.md implementation-plan.md pull-requests.md].freeze

      # Where one file's diff begins.
      FILE = %r{^diff --git a/(?<path>.+?) b/}

      # @param github [Vcs::GitHub] the `gh` seam
      # @param dir [String] where built packets are kept
      # @param diff_limit [Integer]
      # @param document_limit [Integer]
      def initialize(github:, dir: DIR, diff_limit: DIFF_LIMIT, document_limit: DOCUMENT_LIMIT)
        @github = github
        @dir = dir
        @diff_limit = diff_limit
        @document_limit = document_limit
        @mutex = Mutex.new
      end

      # The round's packet: read back when a reviewer of this round already
      # had it, built otherwise. A packet missing a diff is handed over but
      # not kept, so the next reviewer's start tries GitHub again.
      #
      # @param subject [Plans::Subject]
      # @return [String]
      def call(subject)
        @mutex.synchronize do
          path = path_for(subject)
          next File.read(path, encoding: "UTF-8") if File.file?(path)

          @complete = true
          build(subject).tap { keep(path, it) if @complete }
        end
      end

      private

      # @param subject [Plans::Subject]
      # @return [String]
      def build(subject)
        pulls = subject.pull_requests.select { it.open? && it.number }
        <<~PACKET
          # Review packet

          The harness built this once for this review round, and every reviewer
          of the round has the same one. It holds the plan's documents and the
          pull request's diff as they stood when the round began. Your
          instructions follow it.

          ## Plan documents

          #{documents(subject)}

          ## Diff

          #{diffs(pulls)}

          End of the review packet.

          ---

        PACKET
      end

      # @param subject [Plans::Subject]
      # @return [String]
      def documents(subject)
        present = DOCUMENTS.select { subject.file?(it) }
        return "The plan folder holds none of #{DOCUMENTS.join(", ")}." if present.empty?

        present.map { document(it, subject) }.join("\n\n")
      end

      # @param name [String]
      # @param subject [Plans::Subject]
      # @return [String]
      def document(name, subject)
        text = File.read(File.join(subject.feature.path, name), encoding: "UTF-8").scrub.strip
        cut = text.length > @document_limit
        body = cut ? text[0, @document_limit] : text
        note = "\n\n`#{name}` was cut at #{@document_limit} characters. Read the rest in the plan folder." if cut
        "<document name=\"#{name}\">\n#{body}\n</document>#{note}"
      end

      # Every open pull request's diff, sharing one budget in the order
      # `pull-requests.md` lists them.
      #
      # @param pulls [Array<Plans::PullRequest>]
      # @return [String]
      def diffs(pulls)
        return "`pull-requests.md` lists no open pull request, so there is no diff here." if pulls.empty?

        left = @diff_limit
        pulls.map { |pull|
          text = fetch(pull) or next unfetched(pull)

          kept, omitted = fit(text, left)
          left -= kept.length
          "<diff pr=\"#{pull.number}\">\n#{kept.chomp}\n</diff>#{truncation(pull, omitted)}"
        }.join("\n\n")
      end

      # @param pull [Plans::PullRequest]
      # @return [String, nil] nil when `gh` could not say
      def fetch(pull)
        @github.diff(number: pull.number, repo: Vcs::GitHub.repo_of(pull.url)).to_s.scrub
      rescue Error => e
        @complete = false
        UI.log("no diff of ##{pull.number} for the review packet: #{e.message}", level: :warn)
        nil
      end

      # Cuts +text+ to +limit+ at the last whole file that fits, so no
      # reviewer judges half a hunk. One file larger than the limit is cut at
      # a line, since nothing of the diff would be worse.
      #
      # @param text [String]
      # @param limit [Integer]
      # @return [Array(String, Array<String>)] what is kept, and the paths left out
      def fit(text, limit)
        return [text, []] if text.length <= limit

        files = text.split(/^(?=diff --git )/)
        kept = +""
        kept << files.shift while files.first && kept.length + files.first.length <= limit
        kept << files.first[0, limit].sub(/[^\n]*\z/, "") if kept.empty? && files.first
        [kept, files.filter_map { it[FILE, :path] }]
      end

      # @param pull [Plans::PullRequest]
      # @param omitted [Array<String>]
      # @return [String, nil]
      def truncation(pull, omitted)
        return if omitted.empty?

        "\n\nThe diff of ##{pull.number} was cut to fit: this packet carries at most #{@diff_limit} characters of diff. " \
          "Not shown in full, #{omitted.size} #{omitted.size == 1 ? "file" : "files"}:\n\n" \
          "#{omitted.map { "- `#{it}`" }.join("\n")}\n\n" \
          "Run `gh pr diff #{pull.number}` for the rest before you judge those files."
      end

      # @param pull [Plans::PullRequest]
      # @return [String]
      def unfetched(pull) = "The harness could not fetch the diff of ##{pull.number}. Run `gh pr diff #{pull.number}` yourself."

      # @param subject [Plans::Subject]
      # @return [String] one file per plan and review round
      def path_for(subject)
        feature = subject.feature
        plans = Digest::SHA256.hexdigest(File.expand_path(File.dirname(feature.path)))[0, 12]
        File.join(@dir, "#{plans}-#{feature.ordinal}-r#{Plans::PlanState.for(feature.path).moves}.md")
      end

      # Written whole or not at all, and earlier rounds' packets of the same
      # plan go: nothing reads them again. A packet that cannot be kept is
      # only a round that fetches twice, so the failure is logged, not raised.
      #
      # @param path [String]
      # @param text [String]
      # @return [void]
      def keep(path, text)
        FileUtils.mkdir_p(@dir)
        FileUtils.rm_f(Dir.glob(path.sub(/-r\d+\.md\z/, "-r*.md")))
        File.write("#{path}.tmp", text)
        File.rename("#{path}.tmp", path)
      rescue SystemCallError => e
        UI.log("could not keep the review packet: #{e.message}", level: :warn)
      end
    end
  end
end

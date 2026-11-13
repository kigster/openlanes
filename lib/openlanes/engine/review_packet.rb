# frozen_string_literal: true

require "open3"

module OpenLanes
  module Engine
    # What every reviewer used to gather for itself: the pull request's diff
    # and a digest of the plan. Three reviewers each read spec.md, plan.md,
    # contract.md and pull-requests.md and ran `gh pr diff`, three sets of
    # round trips inside a 300-second clock. The harness now builds it once
    # per plan and head commit, and every reviewer's prompt carries the same
    # copy ({Execution::Prompt}).
    #
    # @!attribute [r] head_sha
    #   @return [String, nil] the checkout's HEAD the packet was built at
    # @!attribute [r] diff
    #   @return [String] the pull request's diff, cut at {MAX_DIFF}
    # @!attribute [r] digest
    #   @return [String] the plan's own documents, cut down to what a review needs
    # @!attribute [r] truncated
    #   @return [Boolean] whether the diff was cut
    ReviewPacket = Data.define(:head_sha, :diff, :digest, :truncated) do
      # @return [String] the section a reviewer's prompt carries
      def to_prompt
        <<~MARKDOWN

          ## Review packet, head #{head_sha || "unknown"}

          The harness read the plan and fetched the diff once for every reviewer.
          Review from this. #{truncated ? ReviewPacket::TRUNCATED : "It is the whole diff: do not run `gh pr diff`."}

          ### Plan digest

          #{digest}

          ### Diff

          ```diff
          #{diff}
          ```
        MARKDOWN
      end
    end

    class ReviewPacket
      # Characters of diff a prompt carries before the rest is cut.
      MAX_DIFF = 60_000

      # Characters of contract.md the digest carries.
      MAX_CONTRACT = 8_000

      # What a cut diff tells the reviewer.
      TRUNCATED = "The diff was truncated at #{MAX_DIFF} characters: run `gh pr diff` for the rest.".freeze

      # The spec.md section the digest quotes.
      WORK = "What needs to be done"

      @cache = {}
      @lock = Mutex.new

      class << self
        # @param subject [OpenLanes::Plans::Subject]
        # @param checkout [String] the plan's working tree
        # @param github [#pr_diff] the seam the diff comes through
        # @param head [#call] checkout → HEAD sha
        # @return [OpenLanes::Engine::ReviewPacket] one build per plan and head
        def build(subject, checkout, github: Vcs::GitHub.new(chdir: checkout), head: method(:head_of))
          sha = head.call(checkout)
          key = [subject.feature.ordinal.to_s, sha]
          @lock.synchronize { @cache[key] ||= assemble(subject, sha, github) }
        end

        # Forget every packet, for a suite that builds several.
        #
        # @return [void]
        def reset! = @lock.synchronize { @cache.clear }

        # @param checkout [String]
        # @return [String, nil]
        def head_of(checkout)
          out, status = Open3.capture2("git", "-C", checkout.to_s, "rev-parse", "HEAD", err: File::NULL)
          status.success? ? out.strip : nil
        end

        private

        # @return [OpenLanes::Engine::ReviewPacket]
        def assemble(subject, sha, github)
          pr = subject.pull_requests.find(&:open?)
          diff = pr&.number ? github.pr_diff(number: pr.number).to_s : ""
          new(head_sha: sha, diff: diff[0, MAX_DIFF], digest: Digest.call(subject, pr), truncated: diff.size > MAX_DIFF)
        end
      end

      # The plan's documents, cut to what a review reads.
      module Digest
        module_function

        # @param subject [OpenLanes::Plans::Subject]
        # @param pull [OpenLanes::Plans::PullRequest, nil]
        # @return [String]
        def call(subject, pull)
          [work(subject.read("spec.md")), units(subject.read("plan.md")), contract(subject.read("contract.md")), row(pull)]
            .compact.join("\n\n")
        end

        # @return [String, nil]
        def work(spec)
          body = spec.to_s[/^\#\#[ \t]+#{WORK}[^\n]*\n(.*?)(?=^\#\#[ \t]|\z)/mo, 1]
          body && "#### #{WORK}\n\n#{body.strip}"
        end

        # @return [String, nil]
        def units(plan)
          headings = plan.to_s.lines.grep(/\A\#{3}[ \t]+\S/).map { "- #{it.delete_prefix("###").strip}" }
          headings.empty? ? nil : "#### Units\n\n#{headings.join("\n")}"
        end

        # @return [String, nil]
        def contract(text)
          text && "#### contract.md\n\n#{text.strip[0, MAX_CONTRACT]}"
        end

        # @return [String, nil]
        def row(pull) = pull && "#### Pull request\n\n#{pull.label} (#{pull.state})"
      end
    end
  end
end

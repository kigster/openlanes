# frozen_string_literal: true

require "tty/command"

module OpenLanes
  module Lifecycle
    # A new plan's opening brief: four questions, and a best-effort first pass
    # at answering them from what the project already has on disk.
    #
    # This is for work that does not exist yet. A plan created `--after` a
    # shipped pull request already has its facts — {CLI::Create} hands those to
    # `yoda-writer`, which reconstructs a specification from a diff, not this.
    # Guessing at a diff and guessing at a feature nobody has built are
    # different jobs, and conflating them is how a retroactive spec ends up
    # full of hedges about something that already, provably, happened.
    #
    # The four headings are the brief `leah-researcher` and `yoda-writer` both
    # read *before* their own chapters: what research needs to settle is a
    # question about the gaps in `## What already exists`, so a scaffold
    # missing that heading forces both of them to first reconstruct a boundary
    # this class already had for free — it just created the folder.
    class Brief
      # The half-agent's name. It has no `agents/*.md` of its own on purpose —
      # a roster entry would put it in `Runner`'s routing, and this pass runs
      # only inside `create`. The name exists so the UI can show it the same
      # way it shows `leah-researcher` and `yoda-writer` on their spinner lines.
      AGENT_NAME = "anakin-briefster"

      HEADINGS = [
        "What we are trying to achieve",
        "Why it matters",
        "What already exists",
        "What research needs to settle"
      ].freeze

      # Read whole into the drafting prompt, in order, so the model sees the
      # project's own account of itself before it sees the topic.
      CONTEXT_FILES = %w[CLAUDE.md AGENTS.md README.md].freeze

      # Relative to the repository root. Not every project keeps one — a
      # missing backlog is silently skipped, not an error.
      BACKLOG_FILE = File.join(OpenLanes::PLANS_DIR, "BACKLOG.md")

      # Long enough for a handful of Read/Grep/Glob calls over a local
      # checkout; short enough that a hung `claude` does not stall `create`
      # past the point where the scaffold is already there to open by hand.
      TIMEOUT = 60

      # The fastest model, and the draft is disposable: the prompt prefers an
      # honest blank over a clever inference, so there is no reasoning premium
      # worth paying a larger model for inside a 60-second budget.
      BRIEF_MODEL = "haiku"

      # Read-only, and no `Bash` — this pass surveys what the repository
      # already says about itself, it does not go looking further. That is
      # `leah-researcher`'s job, and denying her tools here is what keeps the
      # two from quietly doing the same work twice.
      ALLOWED_TOOLS = %w[Read Grep Glob Edit].freeze
      DENIED_TOOLS = %w[WebFetch WebSearch Bash].freeze

      # The `stdout:` and `stderr:` sections of a {TTY::Command::ExitError}
      # message. stdout runs until stderr starts; stderr runs to the end, because
      # what `claude` prints there is not guaranteed to be one line.
      STDOUT_SECTION = /^[ \t]*stdout:[ \t]*(.*?)(?=\n[ \t]*stderr:|\z)/m
      STDERR_SECTION = /^[ \t]*stderr:[ \t]*(.*)\z/m

      # How much of what `claude` said survives into a one-line report.
      REASON_LIMIT = 300

      # A one-line account of a failed `claude` run, built from the error rather
      # than its first line: that first line is the escaped prompt, several
      # thousand characters of it, and reporting it says an invocation failed,
      # at length, and never why.
      #
      # Both streams are kept because they carry different halves. `claude`
      # reports its own failures on stdout; the line naming the *cause* of a 401
      # (`ANTHROPIC_API_KEY ... takes precedence over your claude.ai login`) is
      # on stderr. {Executor} used to own this; it now reads a child process
      # directly and has no exit error to parse, so the briefer keeps it.
      #
      # @param error [TTY::Command::ExitError]
      # @return [String]
      def self.failure_reason(error)
        status = error.message[/^[ \t]*exit status:[ \t]*(\S+)/, 1]
        outcome = status ? "exited #{status}" : "failed"
        said = [STDOUT_SECTION, STDERR_SECTION]
               .filter_map { |section| tail(error.message[section, 1]) }
               .join(" | ")

        said.empty? ? "#{outcome} and said nothing" : "#{outcome}: #{said}"
      end

      # @param text [String, nil]
      # @return [String, nil] the last few meaningful lines, on one line
      def self.tail(text)
        lines = text.to_s.split("\n").map(&:strip).reject { |line| line.empty? || line == "Nothing written" }
        return nil if lines.empty?

        joined = lines.last(3).join(" ")
        joined.length > REASON_LIMIT ? "#{joined[0, REASON_LIMIT - 1]}..." : joined
      end
      private_class_method :tail

      # @param path [String] the new plan folder, absolute
      # @param title [String] the feature's proper name, e.g. "Tax Rule DSL"
      # @param root [String] repository root, for project context and `--add-dir`
      # @param command [TTY::Command]
      # @param timeout [Integer] seconds before the drafting attempt is abandoned
      # @param dry_run [Boolean] plan the invocation, do not run it
      # @param seed [String, nil] what the author already wrote about the
      #   feature (`create --from`); opens spec.md and outranks the repo survey
      def initialize(
        path:,
        title:,
        root:,
        command: TTY::Command.new(printer: :null),
        timeout: TIMEOUT,
        dry_run: false,
        seed: nil
      )
        @path = path
        @title = title
        @root = File.expand_path(root)
        @command = command
        @timeout = timeout
        @dry_run = dry_run
        @seed = seed.to_s.strip.then { |s| s.empty? ? nil : s }
      end

      # @return [String]
      attr_reader :path, :title, :root

      # @return [String, nil]
      attr_reader :seed

      # @return [String] absolute path to the spec, whether or not it exists yet
      def spec_path = File.join(path, "spec.md")

      # The title and four empty headings — and, when `create --from` supplied
      # one, the author's own prose between them, so the file already says
      # something even if the drafting attempt never returns.
      #
      # @return [String]
      def scaffold
        opening = seed ? "#{seed}\n\n" : ""
        "# #{title}\n\n#{opening}" + HEADINGS.map { |h| "## #{h}\n\n" }.join("\n")
      end

      # @return [String] where it was written
      def write_scaffold!
        File.write(spec_path, scaffold)
        spec_path
      end

      # Make a best-effort attempt at the four headings, in place, by shelling
      # out to `claude` the same way {Executor} does for a specialist agent.
      # A failure here is not this method's to hide: the scaffold {#write_scaffold!}
      # already wrote stands on its own, so the caller reports the failure and
      # moves on rather than treating it as fatal to `create`.
      #
      # @return [Array(Boolean, String)] ok, and a one-line note
      def attempt!
        return [true, "dry run — would draft from project context"] if @dry_run

        begin
          @command.run(*invocation, timeout: @timeout)
        rescue TTY::Command::TimeoutExceeded
          return [false, "timed out after #{@timeout}s"]
        rescue TTY::Command::ExitError => e
          return [false, "claude #{self.class.failure_reason(e)}"]
        end

        [true, "drafted"]
      end

      # Exposed so a spec can assert the boundary without running anything.
      #
      # @return [Array<String>]
      def invocation
        # Lean for the same reason every agent is: the draft has fifty
        # seconds, and the operator's plugins would spend some of them loading.
        ["claude",
         "-p", prompt, "--add-dir", root,
         "--model", BRIEF_MODEL,
         *Adapters::Claude::LEAN,
         "--allowedTools", ALLOWED_TOOLS.join(","),
         "--disallowedTools", DENIED_TOOLS.join(",")]
      end

      private

      # @return [String]
      def prompt
        <<~PROMPT
          #{author_statement}A new plan folder was just created for a feature that does not exist
          yet: "#{title}".

          You have 50 seconds. Explore the codebase for the first thirty and
          write for the last twenty; the process is killed at sixty and an
          unwritten draft is lost.

          #{spec_path} holds a title and four empty headings:

          #{HEADINGS.map { |h| "  * #{h}" }.join("\n")}

          Make a best-effort first pass at each, drawn only from what THIS
          project already has on disk under #{root} — its own docs, its own
          conventions, code already built, and anything already downloaded or
          gathered that bears on "#{title}". Read/Grep/Glob freely to look for
          it; do not invent facts and do not research the web. Where the
          repository gives you nothing to go on, leave that heading's body as
          a short, honest one-line note saying so, e.g. "_Nothing in the repo
          speaks to this yet — needs research._" A human completes this
          afterward, and a confident-sounding guess costs them more to unwind
          than an honest blank.

          `## What already exists` matters most: name specific files, modules
          or prior work you found, not just that "some code exists" — that is
          exactly the context a researcher picking this up next cannot see for
          themselves without being told where to look.

          #{context}
          #{backlog}
          Edit #{spec_path} in place. Keep the title#{", the author's opening prose" if seed} and the four `##`
          headings exactly as they are, in order; add prose under them; write
          nothing outside them; touch no other file.
        PROMPT
      end

      # The author's own words lead the prompt, ahead of even the feature's
      # announcement, because they outrank everything this pass could survey:
      # where the seed and the repository disagree, the seed is the intent and
      # the repository is merely the past.
      #
      # @return [String] empty without a seed
      def author_statement
        return "" unless seed

        <<~STATEMENT
          The author has already written the following about this feature. It
          is the primary source: where it answers one of the headings, draw
          from it first, and use the repository survey below only to supplement
          it — never to contradict it.

          #{seed}

        STATEMENT
      end

      # AGENTS.md is commonly a symlink to CLAUDE.md; realpath-deduping keeps
      # the shared content from being inlined twice into every drafting prompt.
      #
      # @return [String]
      def context
        seen = []
        found = CONTEXT_FILES.filter_map { |name|
          file = File.join(root, name)
          next unless File.file?(file)

          real = File.realpath(file)
          next if seen.include?(real)

          seen << real
          "### #{name}\n\n#{File.read(file, encoding: "UTF-8")}"
        }
        return "" if found.empty?

        "## Project context\n\n#{found.join("\n\n")}\n"
      end

      # A relevant line in the project's own backlog is worth more than
      # anything this pass could infer on its own — it is the one place "why
      # now" might already be written down.
      #
      # @return [String]
      def backlog
        file = File.join(root, BACKLOG_FILE)
        return "" unless File.file?(file)

        "## #{BACKLOG_FILE}\n\n" \
          "If this backlog mentions \"#{title}\", treat that entry as " \
          "authoritative for `## Why it matters` — it is the project's own " \
          "statement of intent.\n\n" \
          "#{File.read(file, encoding: "UTF-8")}\n"
      end
    end
  end
end

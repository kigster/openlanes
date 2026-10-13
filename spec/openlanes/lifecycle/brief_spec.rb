# frozen_string_literal: true

# Backs the plain (no `--prs`) path of `openlanes create`. `synthesize`
# already has its own coverage through {OpenLanes::Execution::Executor}; these
# examples are the other half of the fork in `CLI::Create#created` — the one
# for a feature that does not exist yet.
RSpec.describe OpenLanes::Lifecycle::Brief, :tree do
  subject(:brief) { described_class.new(path:, title: "Widget Export Flow", root:, command:) }

  let(:root) { File.dirname(plans_root) }
  let!(:path) { plans { |t| t.plan "000.00", :new, "widget-export-flow" } }
  let(:command) { instance_double(TTY::Command, run: nil) }

  describe "#scaffold" do
    let(:rendered) { brief.scaffold }

    it "opens with the title as an H1" do
      expect(rendered.lines.first).to eq("# Widget Export Flow\n")
    end

    it "carries the four headings, verbatim and in order" do
      headings = rendered.scan(/^## (.+)$/).flatten

      expect(headings).to eq(described_class::HEADINGS)
    end

    it "writes nothing else — no Goals, no Research, no prose of its own" do
      body = rendered.sub(/\A# .+\n\n/, "")
      prose = body.split(/^## .+\n+/).reject(&:empty?)

      expect(prose).to be_empty
    end
  end

  describe "#write_scaffold!" do
    it "writes the scaffold to spec.md inside the plan folder" do
      brief.write_scaffold!

      expect(File.read(File.join(path, "spec.md"))).to eq(brief.scaffold)
    end

    it "returns the path it wrote" do
      expect(brief.write_scaffold!).to eq(File.join(path, "spec.md"))
    end
  end

  describe "#invocation" do
    let(:argv) { brief.invocation }

    it "shells out to claude in print mode with the drafting prompt" do
      expect(argv.first(2)).to eq(["claude", "-p"])
    end

    it "scopes the agent to the repository it is drafting from" do
      expect(argv.each_cons(2).to_a).to include(["--add-dir", root])
    end

    it "allows only reading and editing the one file it is meant to touch" do
      expect(argv.each_cons(2).to_a).to include(["--allowedTools", described_class::ALLOWED_TOOLS.join(",")])
    end

    it "pins the fastest model — the draft is disposable, speed is the point" do
      expect(argv.each_cons(2).to_a).to include(["--model", described_class::BRIEF_MODEL])
    end

    it "denies the web and the shell — this is a local survey, not research" do
      expect(argv.each_cons(2).to_a).to include(["--disallowedTools", described_class::DENIED_TOOLS.join(",")])
      expect(described_class::DENIED_TOOLS).to include("WebFetch", "WebSearch", "Bash")
    end

    it "names the topic and every heading in the prompt" do
      prompt = argv[2]

      aggregate_failures do
        expect(prompt).to include("Widget Export Flow")
        described_class::HEADINGS.each { |h| expect(prompt).to include(h) }
      end
    end

    it "tells the agent which file to edit, and to touch no other" do
      expect(argv[2]).to include(brief.spec_path, "touch no other file")
    end

    it "warns it against inventing facts or reaching for the web" do
      expect(argv[2]).to include("do not research the web", "do not invent facts")
    end

    it "tells the drafter it has fifty seconds, ten fewer than the kill" do
      expect(brief.invocation[2]).to include("50 seconds")
      expect(described_class::TIMEOUT).to eq(60)
    end

    context "when the project keeps context files" do
      before { File.write(File.join(root, "CLAUDE.md"), "# Widgets Inc.\n\nWe build widgets.") }

      it "inlines them into the prompt" do
        expect(argv[2]).to include("We build widgets.")
      end
    end

    context "when AGENTS.md is a symlink to CLAUDE.md" do
      before do
        File.write(File.join(root, "CLAUDE.md"), "We build widgets.")
        File.symlink(File.join(root, "CLAUDE.md"), File.join(root, "AGENTS.md"))
      end

      it "inlines the shared content once, not twice" do
        expect(argv[2].scan("We build widgets.").count).to eq(1)
      end
    end

    context "when the project has no context files" do
      it "still produces a usable prompt, just without a project-context section" do
        expect(argv[2]).not_to include("## Project context")
      end
    end

    context "when the project keeps a backlog" do
      before do
        FileUtils.mkdir_p(File.join(root, OpenLanes::PLANS_DIR))
        File.write(File.join(root, described_class::BACKLOG_FILE), "- widget export flow, requested by ops")
      end

      it "inlines it into the prompt" do
        expect(argv[2]).to include("requested by ops")
      end

      it "tells the model the backlog's word on the feature is authoritative" do
        expect(argv[2]).to include("authoritative for `## Why it matters`")
      end
    end

    context "when there is no backlog" do
      it "does not claim there is one" do
        expect(argv[2]).not_to include(described_class::BACKLOG_FILE)
      end
    end

    context "when `create --from` supplied the author's own prose" do
      let(:brief) do
        described_class.new(path:,
          title: "Widget Export Flow",
          root:,
          seed: "Exports must round-trip through the ledger.")
      end

      it "leads the prompt with it, ahead of everything surveyed" do
        prompt = argv[2]

        expect(prompt.index("round-trip through the ledger"))
          .to be < prompt.index("A new plan folder was just created")
      end

      it "ranks it above the repository survey" do
        expect(argv[2]).to include("primary source", "never to contradict it")
      end

      it "tells the model the opening prose is as untouchable as the headings" do
        expect(argv[2]).to include("the author's opening prose")
      end

      it "opens the scaffold with it, so the file says something even if the draft never lands" do
        scaffold = brief.scaffold

        expect(scaffold.index("round-trip through the ledger"))
          .to be < scaffold.index("## What we are trying to achieve")
      end
    end

    context "without a seed" do
      it "carries no author section — an empty banner would read as missing prose" do
        expect(argv[2]).not_to include("primary source")
      end
    end
  end

  describe "#attempt!" do
    it "runs the invocation through the injected command" do
      brief.attempt!

      expect(command).to have_received(:run).with(*brief.invocation, timeout: described_class::TIMEOUT)
    end

    it "reports success without the caller having to inspect the command's own result" do
      expect(brief.attempt!).to eq([true, "drafted"])
    end

    it "turns a timeout into a note rather than an unhandled exception" do
      allow(command).to receive(:run).and_raise(TTY::Command::TimeoutExceeded)

      ok, note = brief.attempt!

      aggregate_failures do
        expect(ok).to be(false)
        expect(note).to include("timed out")
      end
    end

    it "turns a non-zero exit into a note rather than an unhandled exception" do
      allow(command).to receive(:run).and_raise(TTY::Command::ExitError.new("claude",
        instance_double(TTY::Command::Result, exit_status: 1, out: "", err: "boom")))

      ok, note = brief.attempt!

      aggregate_failures do
        expect(ok).to be(false)
        expect(note).to include("exited 1")
      end
    end

    # `create` shells out to `claude` the same way {Executor} does, so it had
    # the same bug. The first line of the error is the escaped prompt.
    # Reporting it said an invocation failed, at length, and never why.
    it "reports what claude said, not the several-thousand-character prompt it said it about" do
      allow(command).to receive(:run).and_raise(TTY::Command::ExitError.new("claude -p #{"x" * 3000}",
        instance_double(TTY::Command::Result,
          exit_status: 1,
          out:         "API Error: 401 API key is invalid.",
          err:         "")))

      ok, note = brief.attempt!

      aggregate_failures do
        expect(ok).to be(false)
        expect(note).to include("401 API key is invalid.")
        expect(note).not_to include("xxx")
      end
    end

    context "with dry_run: true" do
      subject(:brief) { described_class.new(path:, title: "Widget Export Flow", root:, command:, dry_run: true) }

      it "never touches the command" do
        brief.attempt!

        expect(command).not_to have_received(:run)
      end

      it "still reports success, so a dry-run create does not read as a failed one" do
        expect(brief.attempt!.first).to be(true)
      end
    end
  end
end

# frozen_string_literal: true

# `openlanes create` is the one command where a mistake becomes permanent: the
# folder name it mints is the number everything else joins on. These examples
# pin down the paths that refuse — bad flags, unfetchable pull requests, an
# empty slug — as firmly as the paths that create, because a refusal that
# creates anyway is the bug the whole command is shaped to prevent.
RSpec.describe OpenLanes::CLI::Create, :tree do
  subject(:command) { described_class.new }

  def run(*words, **)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0

    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(words:, dir: plans_root, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end

    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  # The boxes wrap on words at the terminal's width, so a sentence assertion
  # has to read them back unwrapped or it passes and fails by screen size.

  # `--open` shells out to macOS `open`, which would put a real editor window
  # on the box running the suite. The stub also lets an example assert the
  # viewer was asked for, which "nothing visibly happened" cannot. The
  # platform gate is stubbed too: CI runs on Linux, where the command would
  # otherwise skip the viewer and the example would assert against nothing.
  def intercept_open
    opened = []
    allow(command).to receive(:macos?).and_return(true)
    allow(command).to receive(:system) { |*args|
      opened << args
      true
    }
    opened
  end

  describe "choosing a lane" do
    let(:spec_md) do
      out, = run("split", "big", "migration", starts: "building", depth: "fast", draft: false, open: false)
      File.read(File.join(out.strip, "spec.md"))
    end

    it "writes the lane and depth into spec.md's frontmatter" do
      expect(OpenLanes::Plans::Spec.parse(spec_md).to_h.slice(:starts, :depth)).to eq(starts: :building, depth: :fast)
    end

    it "keeps the scaffold below the frontmatter" do
      expect(spec_md).to include("# Split Big Migration")
    end

    it "writes only created: when no lane or depth was given" do
      out, = run("plain", "plan", draft: false, open: false)
      expect(File.read(File.join(out.strip, "spec.md"))).to start_with("---\ncreated: #{Date.today.iso8601}\n---\n\n# ")
    end
  end

  describe "a brand-new feature, nothing shelled out" do
    it "prints the folder path on STDOUT, where a script can read it" do
      out, = run("tax", "rule", "dsl", draft: false, open: false)

      expect(out.strip).to eq(File.join(plans_root, "000.00━━⚪━━❯tax-rule-dsl"))
    end

    it "writes the four-heading scaffold, so the folder is honest about ⚪" do
      out, = run("tax", "rule", "dsl", draft: false, open: false)

      expect(File.read(File.join(out.strip, "spec.md"))).to include(
        "# Tax Rule DSL", "## What we are trying to achieve", "## What research needs to settle"
      )
    end

    it "says what to do next: the headings are there and still empty" do
      _out, err, = run("tax", "rule", "dsl", draft: false, open: false)

      expect(unwrapped(err)).to include("fill in the four headings", "researcher")
    end

    it "numbers after the plans already there, never over them" do
      plans { |t| t.plan("007.00", :new, "earlier", files: { "spec.md" => spec_body }) }
      out, = run("next", "thing", draft: false, open: false)

      expect(File.basename(out.strip)).to start_with("008.00")
    end

    it "opens the spec in the system viewer unless told not to" do
      opened = intercept_open
      out, = run("tax", "rule", "dsl", draft: false, open: true)

      expect(opened.map { |args| args.first(2) }).to include(["open", File.join(out.strip, "spec.md")])
    end

    it "prints only the path under --quiet, so the output stays a value" do
      out, err, = run("tax", "rule", "dsl", draft: false, open: false, quiet: true)

      expect(out.lines.size).to eq(1)
      expect(err).to eq("")
    end
  end

  describe "--status" do
    it "opens the folder in the named state instead of ⚪" do
      out, = run("billing", "sync", status: "planned", draft: false, open: false)

      expect(File.basename(out.strip)).to include("⭐")
    end
  end

  describe "the drafting attempt" do
    # A real draft shells out to `claude` for minutes; the Brief is replaced so
    # these examples assert only the seam: attempted, and reported honestly.
    def with_brief(result:)
      brief = instance_double(OpenLanes::Lifecycle::Brief,
        write_scaffold!: nil,
        stamp!:          nil,
        attempt!:        result,
        spec_path:       File.join(plans_root, "irrelevant", "spec.md"))
      allow(OpenLanes::Lifecycle::Brief).to receive(:new).and_return(brief)
      brief
    end

    it "asks the brief for a best-effort pass by default" do
      brief = with_brief(result: [true, "drafted"])
      run("tax", "rule", "dsl", open: false)

      expect(brief).to have_received(:attempt!)
    end

    # The half-agent wears its name on the spinner line the way roster agents
    # do on theirs, so a `create` reads like any other agent at work. The line
    # itself only draws on a TTY, so the seam is the phrase handed to the UI.
    it "names anakin-briefster on the progress line" do
      with_brief(result: [true, "drafted"])
      allow(OpenLanes::UI).to receive(:concurrently).and_call_original

      run("tax", "rule", "dsl", open: false)

      expect(OpenLanes::UI).to have_received(:concurrently)
        .with(anything, a_string_including(OpenLanes::Lifecycle::Brief::AGENT_NAME), hash_including(jobs: 1))
    end

    # The scaffold survives a failed draft, so the failure must not read as a
    # failed `create` — the folder is fine, only the convenience fell through.
    it "reports a draft that did not finish without failing the create" do
      with_brief(result: [false, "timed out after 240s"])
      out, err, status = run("tax", "rule", "dsl", open: false)

      expect(out.strip).to end_with("000.00━━⚪━━❯tax-rule-dsl")
      expect(unwrapped(err)).to include("timed out after 240s", "Fill them in by hand")
      expect(status).to eq(0)
    end
  end

  describe "--from a seed file" do
    def seed_file(content)
      File.join(Dir.mktmpdir("seed"), "notes.md").tap { |f| File.write(f, content) }
    end

    let(:seeded) do
      seed_file(<<~MD)
        ---
        title: Tax Rule DSL
        ---
        Rules should read like the statute they encode.
      MD
    end

    it "names the folder from the frontmatter title, no words needed" do
      out, = run(from: seeded, draft: false, open: false)

      expect(File.basename(out.strip)).to eq("000.00━━⚪━━❯tax-rule-dsl")
    end

    it "opens spec.md with the author's own prose, ahead of the headings" do
      out, = run(from: seeded, draft: false, open: false)
      spec = File.read(File.join(out.strip, "spec.md"))

      expect(spec.index("statute they encode")).to be < spec.index("## What we are trying to achieve")
    end

    it "hands the seed on to the drafting prompt as the primary source" do
      captured = nil
      allow(OpenLanes::Lifecycle::Brief).to(receive(:new).and_wrap_original { |m, **kw|
        captured = kw[:seed]
        m.call(**kw)
      })
      run(from: seeded, draft: false, open: false)

      expect(captured).to include("statute they encode")
    end

    it "refuses words and --from together — two answers to one name" do
      _out, err, status = run("tax", "rule", "dsl", from: seeded, draft: false, open: false)

      expect(unwrapped(err)).to include("drop the words, or drop --from")
      expect(status).to eq(64)
    end

    it "refuses a file that is not there, before minting anything" do
      _out, err, status = run(from: "/no/such/notes.md", draft: false, open: false)

      expect(unwrapped(err)).to include("does not exist")
      expect(status).to eq(66)
      expect(Dir.children(plans_root)).to be_empty
    end

    it "refuses a seed with no frontmatter title — the folder needs a name" do
      bare = seed_file("Just prose, no frontmatter.")
      _out, err, status = run(from: bare, draft: false, open: false)

      expect(unwrapped(err)).to include("frontmatter title")
      expect(status).to eq(65)
    end

    # A seed file written by hand carries a `date:`, and `YAML.safe_load` used
    # to refuse to build one — so a file with a perfectly good title was turned
    # away for not having a title.
    it "names the folder from a title that shares its frontmatter with a date" do
      dated = seed_file(<<~MD)
        ---
        title: Tax Rule DSL
        date: 2026-08-31
        author: Alan Turing
        ---
        Rules should read like the statute they encode.
      MD
      out, _err, status = run(from: dated, draft: false, open: false)

      expect(File.basename(out.strip)).to eq("000.00━━⚪━━❯tax-rule-dsl")
      expect(status).to eq(0)
    end

    it "says the frontmatter is not YAML, rather than blaming the title" do
      broken = seed_file("---\ntitle: [unclosed\n---\nbody\n")
      _out, err, status = run(from: broken, draft: false, open: false)

      expect(unwrapped(err)).to include("not valid YAML")
      expect(status).to eq(65)
    end
  end

  describe "a topic that produces nothing" do
    it "refuses rather than minting a folder with no name" do
      _out, err, status = run("---", draft: false, open: false)

      expect(unwrapped(err)).to include("Could not create the plan", "empty slug")
      expect(status).to eq(65)
    end
  end

  describe "--prs" do
    let(:github) { instance_double(OpenLanes::Vcs::GitHub) }

    before { allow(OpenLanes::Vcs::GitHub).to receive(:new).and_return(github) }

    # A retroactive plan documents work that landed somewhere in the sequence,
    # and only its author knows where. Refusing without --after is the guard
    # against the tool guessing that position.
    it "refuses without --after, naming the flag that is missing" do
      _out, err, status = run("verify", prs: "12")

      expect(unwrapped(err)).to include("--after")
      expect(status).to eq(64)
    end

    it "reports pull requests it could not read, not a stack trace" do
      allow(github).to receive(:pull_requests)
        .and_raise(OpenLanes::Error, "could not read pull request 12: gone")
      plans { |t| t.plan("002.00", :new, "anchor", files: { "spec.md" => spec_body }) }
      _out, err, status = run("verify", after: "002", prs: "12")

      expect(unwrapped(err)).to include("could not read pull request 12")
      expect(status).to eq(65)
    end

    context "with the pull requests fetched" do
      let(:pull) do
        { number: 12, title: "Verify things", url: "https://github.com/example/repo/pull/12",
         state: "Open 🟡", body: "" }
      end

      before do
        allow(github).to receive(:pull_requests).with(["12"]).and_return([pull])
        plans { |t| t.plan("002.00", :new, "anchor", files: { "spec.md" => spec_body }) }
      end

      it "records the pull requests and stops under --no-spec, offline" do
        out, = run("verify", after: "002", prs: "12", spec: false, open: false)

        expect(File.basename(out.strip)).to start_with("002.01")
        expect(File.read(File.join(out.strip, "pull-requests.md"))).to include("Verify things")
      end

      # `--prs` with `--spec` hands the folder to spec-writer. The executor is
      # replaced so the suite never invokes `claude`; the double writing
      # spec.md is what the agent would have done.
      def with_executor(result: [true, "completed"], &edit)
        executor = instance_double(OpenLanes::Execution::Executor)
        allow(executor).to receive(:call) do |_agent, subject, **|
          edit&.call(subject)
          result
        end
        allow(OpenLanes::Execution::Executor).to receive(:new).and_return(executor)
      end

      it "writes spec.md via the retroactive writer and resettles the folder" do
        with_executor { |subject| File.write(File.join(subject.feature.path, "spec.md"), spec_body) }
        out, err, = run("verify", after: "002", prs: "12", open: false)

        # ⏪ is only true while there is no spec.md, so the settle renames.
        expect(File.basename(out.strip)).to include("⚪")
        expect(unwrapped(err)).to include("check it against what actually shipped")
      end

      it "reports a writer that failed, with the pull requests still recorded" do
        with_executor(result: [false, "claude exited 1: 401 API key is invalid"])
        out, err, status = run("verify", after: "002", prs: "12", open: false)

        expect(unwrapped(err)).to include("spec.md was not written", "401 API key is invalid")
        expect(File.exist?(File.join(out.strip, "pull-requests.md"))).to be(true)
        expect(status).to eq(0)
      end
    end
  end
end

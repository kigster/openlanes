# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::Init do
  subject(:command) { described_class.new }

  let(:top) { File.realpath(Dir.mktmpdir("openlanes-init")) }
  let(:repo) { File.join(top, "acme-app") }
  let(:file) { File.join(repo, ".openlanes.yml") }
  let(:tty) { false }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:ready) { true }
  let(:machine) { instance_double(OpenLanes::Setup::Machine, ready?: ready) }
  # What every run without a flag for them records for the new keys. Quality
  # stays unset under -y, to be asked on the first review-passed review (R4).
  let(:decided) { { "merge" => { "by" => "human" } } }

  before do
    FileUtils.mkdir_p(File.join(repo, ".git"))
    FileUtils.mkdir_p(File.join(repo, "lib"))
    Dir.chdir(File.join(repo, "lib"))
    allow(TTY::Prompt).to receive(:new).and_return(prompt)
    allow($stdin).to receive(:tty?).and_return(tty)
    allow(OpenLanes::Setup).to receive(:machine).and_return(machine)
  end

  after { FileUtils.rm_rf(top) }

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    terminal = tty
    err.define_singleton_method(:tty?) { terminal }
    status = 0
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(dry_run: false, yes: false, overwrite: false, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  def written = YAML.safe_load_file(file)

  context "with a ready machine" do
    it "does not run setup" do
      allow(machine).to receive(:call)
      run
      expect(machine).not_to have_received(:call)
    end
  end

  context "with a machine missing a tool" do
    let(:ready) { false }
    let(:gh) { OpenLanes::Setup::Check.new(name: "gh", ok: true, detail: "gh auth status passes", fix: nil) }

    before do
      allow(machine).to receive(:call) { |dry_run:| OpenLanes::Setup::Machine::Outcome.new(missing: %w[jq], installed: !dry_run, checks: [gh]) }
    end

    it "runs setup before its interview, then writes the file" do
      _out, err, = run
      expect(machine).to have_received(:call).with(dry_run: false)
      expect(err).to include("running openlanes setup first", "✓ gh")
      expect(written).to eq("project" => "acme-app", "starts" => "research", **decided)
    end

    it "installs nothing on a dry run" do
      run(dry_run: true)
      expect(machine).to have_received(:call).with(dry_run: true)
    end

    it "neither checks nor runs setup under --no-setup" do
      run(setup: false)
      expect(machine).not_to have_received(:ready?)
      expect(machine).not_to have_received(:call)
    end

    context "when setup cannot fix it" do
      let(:gh) { OpenLanes::Setup::Check.new(name: "gh", ok: false, detail: "gh is not logged in", fix: "gh auth login") }

      it "says so and carries on" do
        _out, err, status = run
        expect(err).to include("fix: gh auth login", "Still not ready")
        expect(status).to eq(0)
        expect(File).to exist(file)
      end
    end
  end

  context "without a terminal" do
    it "writes the file at the repository root, not where it was typed" do
      run
      expect(written).to eq("project" => "acme-app", "starts" => "research", **decided)
    end

    it "creates the plans directory beside it" do
      run
      expect(File.directory?(File.join(repo, ".plans"))).to be(true)
    end

    it "prints the path it wrote on STDOUT" do
      expect(run.first).to eq("#{file}\n")
    end

    it "takes every value as a flag" do
      run(project: "Acme", starts: "building", frontend: false, jobs: "4", quality: "mvp")
      expect(written).to eq("project" => "Acme",
        "starts" => "building",
        "frontend" => false,
        "jobs" => 4,
        "desired_codebase_quality" => "mvp",
**decided)
    end

    it "writes a file every other command can read" do
      run(starts: "planning", jobs: "2")
      expect(OpenLanes::Config.load(repo)).to have_attributes(starts: :planning, jobs: 2)
    end

    it "refuses jobs that are not a count" do
      expect(run(jobs: "many").last).to eq(64)
    end

    it "asks nothing" do
      run
      expect(TTY::Prompt).not_to have_received(:new)
    end

    it "leaves desired_codebase_quality unset, to be asked on the first ok-not-perfect review" do
      run
      expect(OpenLanes::Config.load(repo)).to have_attributes(quality_unset?: true)
      expect(File).not_to exist(File.join(repo, ".plans", "decisions.md"))
    end

    it "takes standard and writes the choice, with all three options, into decisions.md" do
      run(quality: "standard")
      aggregate_failures do
        expect(OpenLanes::Config.load(repo)).to have_attributes(desired_codebase_quality: :standard)
        expect(File.read(File.join(repo, ".plans", "decisions.md")))
          .to include("## desired_codebase_quality: standard", "Decided by openlanes init", "a) high: ", "c) mvp: ")
      end
    end
  end

  context "without a repository" do
    before do
      FileUtils.rm_rf(File.join(repo, ".git"))
      Dir.chdir(repo)
    end

    it "writes in the current directory" do
      run
      expect(File.file?(file)).to be(true)
    end
  end

  context "when .openlanes.yml already exists" do
    before { File.write(file, "project: Kept\n") }

    it "keeps it" do
      _out, err, = run(project: "New")
      expect([written, unwrapped(err)]).to match([{ "project" => "Kept" }, include("Kept", "--overwrite replaces")])
    end

    it "replaces it under --overwrite" do
      run(project: "New", overwrite: true)
      expect(written["project"]).to eq("New")
    end
  end

  describe "-n" do
    subject(:result) { run(dry_run: true, project: "Acme") }

    it "prints the file and writes nothing" do
      out, err, = result
      expect([out, unwrapped(err), File.exist?(file), Dir.exist?(File.join(repo, ".plans"))])
        .to match([start_with("project: Acme\nstarts: research\nmerge:\n  by: human\n"),
                   include("nothing was written", "Would write"), false, false])
    end
  end

  context "with a terminal" do
    let(:tty) { true }
    let(:answer) { "YES" }

    before do
      allow(prompt).to receive(:multi_select).and_return([])
      allow(prompt).to receive(:ask).with("Project name:", default: "acme-app").and_return("Acme")
      allow(prompt).to receive(:ask).with(/Plans to run at once/, convert: :int).and_return(3)
      allow(prompt).to receive(:select).with(/How much detail/, anything, any_args).and_return("low")
      allow(prompt).to receive(:select).with(/WANTED, Layout/, anything, any_args).and_return("library")
      allow(prompt).to receive(:select).with(/Where a new plan starts/, anything, any_args).and_return("planning")
      allow(prompt).to receive(:select).with(/desired quality of the codebase/, anything, any_args).and_return("high")
      allow(prompt).to receive(:select).with(/\AWrite /, %w[YES NO]).and_return(answer)
      allow(prompt).to receive(:select).with(/merges/, anything, any_args).and_return("auto")
      allow(OpenLanes::Setup).to receive(:extractor).and_return(nil)
    end

    it "asks for each value and writes the answers" do
      run
      expect(written).to eq("project" => "Acme",
        "starts" => "planning",
        "jobs" => 3,
        "merge" => { "by" => "auto" },
        "desired_codebase_quality" => "high",
        "architecture_decisions" => { "version" => 1, "detail" => "low", "current" => {}, "target" => { "layout" => "library" } })
    end

    it "asks only for what no flag gave" do
      run(project: "Flagged",
        starts: "building",
        frontend: true,
        jobs: "2",
        ci: "none",
        merge_by: "human",
        quality: "mvp")
      expect(prompt).not_to have_received(:select).with(/merges|desired quality|Where a new plan starts/, any_args)
      expect(prompt).not_to have_received(:ask).with(/Project name|Plans to run/, any_args)
    end

    context "when the answer is NO" do
      let(:answer) { "NO" }

      it "writes nothing" do
        run
        expect(File.exist?(file)).to be(false)
      end
    end

    context "with -y" do
      it "asks nothing and builds no extractor" do
        run(yes: true)
        expect(prompt).not_to have_received(:select)
        expect(OpenLanes::Setup).not_to have_received(:extractor)
      end
    end
  end

  describe "the new decisions under -y" do
    it "takes each from its flag" do
      run(yes: true, ci: "jenkins", merge_by: "auto", quality: "mvp")
      expect(written).to include("merge" => { "by" => "auto" }, "desired_codebase_quality" => "mvp")
      expect(written.dig("architecture_decisions", "target", "ci")).to eq(%w[jenkins])
    end

    it "scaffolds the CI file it records, installing the stack's dependencies" do
      File.write(File.join(repo, "Gemfile"), "")
      run(yes: true, ci: "circleci")
      expect(File.read(File.join(repo, ".circleci/config.yml"))).to include("bundle install", "bundle exec rspec")
    end

    it "writes no CI file, and says why, when nothing would be checked" do
      _out, err, = run(yes: true, ci: "circleci")
      expect([written.dig("architecture_decisions", "target", "ci"), File.exist?(File.join(repo, ".circleci/config.yml")), unwrapped(err)])
        .to match([%w[circleci], false, include("no CI file was written")])
    end

    it "scaffolds a Rails app with a package.json as Ruby" do
      File.write(File.join(repo, "Gemfile"), "")
      File.write(File.join(repo, "package.json"), "{}")
      run(yes: true, ci: "github_actions")
      expect([written.dig("architecture_decisions", "target", "languages"), File.read(File.join(repo, ".github/workflows/ci.yml"))])
        .to match([%w[ruby node], include("bundle exec rubocop")])
    end

    it "names the CI the folder already runs, and leaves it alone" do
      FileUtils.mkdir_p(File.join(repo, ".github/workflows"))
      File.write(File.join(repo, ".github/workflows/test.yml"), "mine\n")
      run(yes: true)
      expect([written.dig("architecture_decisions", "current", "ci"), File.exist?(File.join(repo, ".github/workflows/ci.yml"))])
        .to eq([%w[github_actions], false])
    end

    it "records the detected stack and writes stack.md" do
      File.write(File.join(repo, "Gemfile"), "")
      run(yes: true)
      expect([written.dig("architecture_decisions", "current", "languages"), File.read(File.join(repo, "docs/decisions/stack.md"))])
        .to match([%w[ruby], include("- **Language:** ruby")])
    end

    it "writes no stack and no stack.md for an unknown stack" do
      run(yes: true)
      expect([written.key?("stack"), File.exist?(File.join(repo, "docs/decisions/stack.md"))]).to eq([false, false])
    end

    {
      { ci: "travis" }       => /--ci must be one of/,
      { merge_by: "robot" }  => /--merge-by must be one of/,
      { quality: "perfect" } => /--quality must be one of/
    }.each do |flags, message|
      it "refuses #{flags}" do
        _out, err, status = run(yes: true, **flags)
        expect([status, err, File.exist?(file)]).to match([64, message, false])
      end
    end
  end

  describe "--reconfigure" do
    before do
      File.write(file, "project: Acme\nstarts: planning\nmerge:\n  by: auto\ndesired_codebase_quality: mvp\n")
    end

    # Keys the interview never asks about, which --reconfigure once dropped.
    let(:unasked) do
      <<~YAML
        project: Acme
        starts: planning
        merge:
          by: auto
          max_rejections: 3
        review:
          max_hmm: 2
        questions:
          model: claude-sonnet-4-5
        coverage:
          command: bundle exec rspec
          report: coverage/.resultset.json
          format: simplecov
          minimum: 90
      YAML
    end

    it "keeps the current answers, changes the flagged one, and prints the diff under -y" do
      out, = run(reconfigure: true, yes: true, quality: "high")
      expect([out, written]).to match([include("- desired_codebase_quality: mvp", "+ desired_codebase_quality: high"),
                                       include("project" => "Acme",
                                         "starts" => "planning",
                                         "merge" => { "by" => "auto" },
                                         "desired_codebase_quality" => "high")])
    end

    it "previews under -n and writes nothing" do
      before = File.read(file)
      out, err, = run(reconfigure: true, yes: true, dry_run: true, quality: "high")
      expect([out, err, File.read(file)]).to match([include("+ desired_codebase_quality: high"), include("nothing was written"),
                                                    before])
    end

    it "shows the new stack.md in the diff" do
      File.write(File.join(repo, "Gemfile"), "")
      out, = run(reconfigure: true, yes: true)
      expect(out).to include("docs/decisions/stack.md", "+ - **Language:** ruby")
    end

    it "keeps every key the interview does not ask about" do
      File.write(file, unasked)
      run(reconfigure: true, yes: true, quality: "high")
      expect(written).to include("merge" => { "by" => "auto", "max_rejections" => 3 },
        "review" => { "max_hmm" => 2 },
        "questions" => { "model" => "claude-sonnet-4-5" },
        "coverage" => include("minimum" => 90))
    end

    it "shows the CI file it would write in the diff" do
      File.write(File.join(repo, "Gemfile"), "")
      out, = run(reconfigure: true, yes: true, ci: "jenkins")
      expect(out).to include("Jenkinsfile", "+ ", "bundle install")
    end

    it "lists a moved line rather than hiding it" do
      File.write(file, "starts: planning\nproject: Acme\nmerge:\n  by: auto\ndesired_codebase_quality: mvp\n")
      out, = run(reconfigure: true, yes: true, quality: "mvp")
      expect(out.lines.map(&:chomp)).to include("- project: Acme", "+ project: Acme")
    end

    it "says so when nothing changes" do
      run(reconfigure: true, yes: true)
      out, = run(reconfigure: true, yes: true)
      expect(out).to start_with("No changes.")
    end
  end
end

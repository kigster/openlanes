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
  # stays unset under -y, to be asked on the first ok-not-perfect review (R4).
  let(:decided) { { "merge" => { "by" => "human" }, "ci" => { "provider" => "none" } } }

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
      expect(written).to eq("project" => "acme-app", "lane" => "full", **decided)
    end

    it "installs nothing on a dry run" do
      run(dry_run: true)
      expect(machine).to have_received(:call).with(dry_run: true)
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
      expect(written).to eq("project" => "acme-app", "lane" => "full", **decided)
    end

    it "creates the plans directory beside it" do
      run
      expect(File.directory?(File.join(repo, ".plans"))).to be(true)
    end

    it "prints the path it wrote on STDOUT" do
      expect(run.first).to eq("#{file}\n")
    end

    it "takes every value as a flag" do
      run(project: "Acme", lane: "quick", frontend: false, jobs: "4", quality: "mvp")
      expect(written).to eq("project" => "Acme",
        "lane" => "quick",
        "frontend" => false,
        "jobs" => 4,
        "desired_codebase_quality" => "mvp",
**decided)
    end

    it "writes a file every other command can read" do
      run(lane: "plan", jobs: "2")
      expect(OpenLanes::Config.load(repo)).to have_attributes(lane: :plan, jobs: 2)
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
        .to match([start_with("project: Acme\nlane: full\nmerge:\n  by: human\n"),
                   include("nothing was written", "Would write"), false, false])
    end
  end

  context "with a terminal" do
    let(:tty) { true }
    let(:answer) { "YES" }

    before do
      allow(prompt).to receive(:ask).with("Project name:", default: "acme-app").and_return("Acme")
      allow(prompt).to receive(:ask).with(/Plans to run at once/, default: nil).and_return("3")
      allow(prompt).to receive(:select).with(/Default lane/, %w[full plan quick], default: "full").and_return("plan")
      allow(prompt).to receive(:select).with(/front end/, ["each plan decides", "YES", "NO"], default: "each plan decides")
                                       .and_return("NO")
      allow(prompt).to receive(:select).with(/desired quality of the codebase/, hash_including, any_args).and_return("high")
      allow(prompt).to receive(:select).with(/\AWrite /, %w[YES NO]).and_return(answer)
      allow(prompt).to receive(:select).with(/CI setup/, anything).and_return("No CI for now")
      allow(prompt).to receive(:select).with(/merges/, %w[human auto], default: "human").and_return("auto")
      allow(prompt).to receive(:ask).with(/\A(Language|Frameworks|Front end|Persistence|Caching|Logins|Deployment|Domain)/,
        default: nil).and_return("")
      allow(OpenLanes::Setup).to receive(:extractor).and_return(nil)
    end

    it "asks for each value and writes the answers" do
      run
      expect(written).to eq("project" => "Acme",
        "lane" => "plan",
        "frontend" => false,
        "jobs" => 3,
        "merge" => { "by" => "auto" },
        "ci" => { "provider" => "none" },
        "desired_codebase_quality" => "high")
    end

    it "asks only for what no flag gave" do
      run(project: "Flagged",
        lane: "quick",
        frontend: true,
        jobs: "2",
        ci: "none",
        merge_by: "human",
        quality: "mvp")
      expect(prompt).not_to have_received(:select).with(/CI setup|merges|desired quality|Default lane/, any_args)
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
      expect(written).to include("merge" => { "by" => "auto" },
        "desired_codebase_quality" => "mvp",
        "ci" => { "provider" => "jenkins", "config" => "Jenkinsfile" })
    end

    it "scaffolds the CI file it records, installing the stack's dependencies" do
      File.write(File.join(repo, "Gemfile"), "")
      run(yes: true, ci: "circleci")
      expect(File.read(File.join(repo, ".circleci/config.yml"))).to include("bundle install", "bundle exec rspec")
    end

    it "writes no CI file, and says why, when nothing would be checked" do
      _out, err, = run(yes: true, ci: "circleci")
      expect([written["ci"], File.exist?(File.join(repo, ".circleci/config.yml")), unwrapped(err)])
        .to match([{ "provider" => "circleci", "config" => ".circleci/config.yml" }, false, include("no CI file was written")])
    end

    it "scaffolds a Rails app with a package.json as Ruby" do
      File.write(File.join(repo, "Gemfile"), "")
      File.write(File.join(repo, "package.json"), "{}")
      run(yes: true, ci: "github_actions")
      expect([written["stack"], File.read(File.join(repo, ".github/workflows/ci.yml"))])
        .to match([{ "language" => "ruby" }, include("bundle exec rubocop")])
    end

    it "names the CI the folder already runs, and leaves it alone" do
      FileUtils.mkdir_p(File.join(repo, ".github/workflows"))
      File.write(File.join(repo, ".github/workflows/test.yml"), "mine\n")
      _out, err, = run(yes: true)
      expect([written["ci"], err, File.exist?(File.join(repo, ".github/workflows/ci.yml"))])
        .to match([{ "provider" => "github_actions", "config" => ".github/workflows/test.yml" },
                   include("GitHub Actions"), false])
    end

    it "records the detected stack and writes stack.md" do
      File.write(File.join(repo, "Gemfile"), "")
      run(yes: true)
      expect([written["stack"], File.read(File.join(repo, "docs/decisions/stack.md"))])
        .to match([{ "language" => "ruby" }, include("- **Language:** ruby")])
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
      File.write(file, "project: Acme\nlane: plan\nmerge:\n  by: auto\ndesired_codebase_quality: mvp\n")
    end

    # Keys the interview never asks about, which --reconfigure once dropped.
    let(:unasked) do
      <<~YAML
        project: Acme
        lane: plan
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
                                         "lane" => "plan",
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
      File.write(file, "lane: plan\nproject: Acme\nmerge:\n  by: auto\ndesired_codebase_quality: mvp\n")
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

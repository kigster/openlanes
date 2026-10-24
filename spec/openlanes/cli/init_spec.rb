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
      expect(written).to eq("project" => "acme-app", "starts" => "research")
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
      expect(written).to eq("project" => "acme-app", "starts" => "research")
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
      expect(written).to eq("project" => "Acme", "starts" => "building", "frontend" => false, "jobs" => 4, "desired_codebase_quality" => "mvp")
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
        .to match(["project: Acme\nstarts: research\n", include("nothing was written", "Would write"), false, false])
    end
  end

  context "with a terminal" do
    let(:tty) { true }
    let(:answer) { "YES" }

    before do
      allow(prompt).to receive(:ask).with("Project name:", default: "acme-app").and_return("Acme")
      allow(prompt).to receive(:ask).with(/Plans to run at once/).and_return("3")
      allow(prompt).to receive(:select).with(/Where a new plan starts/, %w[research planning building]).and_return("planning")
      allow(prompt).to receive(:select).with(/front end/, ["each plan decides", "YES", "NO"]).and_return("NO")
      allow(prompt).to receive(:select).with(/desired quality of the codebase/, hash_including).and_return("high")
      allow(prompt).to receive(:select).with(/\AWrite /, %w[YES NO]).and_return(answer)
    end

    it "asks for each value and writes the answers" do
      run
      expect(written).to eq("project" => "Acme", "starts" => "planning", "frontend" => false, "jobs" => 3, "desired_codebase_quality" => "high")
    end

    it "asks only for what no flag gave" do
      run(project: "Flagged", starts: "building", frontend: true, jobs: "2", quality: "mvp")
      expect(prompt).not_to have_received(:ask)
    end

    context "when the answer is NO" do
      let(:answer) { "NO" }

      it "writes nothing" do
        run
        expect(File.exist?(file)).to be(false)
      end
    end

    context "with -y" do
      it "asks nothing" do
        run(yes: true)
        expect(prompt).not_to have_received(:select)
      end
    end
  end
end

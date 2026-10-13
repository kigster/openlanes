# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::Init do
  subject(:command) { described_class.new }

  let(:top) { File.realpath(Dir.mktmpdir("openlanes-init")) }
  let(:repo) { File.join(top, "acme-app") }
  let(:file) { File.join(repo, ".openlanes.yml") }
  let(:tty) { false }
  let(:prompt) { instance_double(TTY::Prompt) }

  before do
    FileUtils.mkdir_p(File.join(repo, ".git"))
    FileUtils.mkdir_p(File.join(repo, "lib"))
    Dir.chdir(File.join(repo, "lib"))
    allow(TTY::Prompt).to receive(:new).and_return(prompt)
    allow($stdin).to receive(:tty?).and_return(tty)
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

  context "without a terminal" do
    it "writes the file at the repository root, not where it was typed" do
      run
      expect(written).to eq("project" => "acme-app", "lane" => "full")
    end

    it "creates the plans directory beside it" do
      run
      expect(File.directory?(File.join(repo, ".plans"))).to be(true)
    end

    it "prints the path it wrote on STDOUT" do
      expect(run.first).to eq("#{file}\n")
    end

    it "takes every value as a flag" do
      run(project: "Acme", lane: "quick", frontend: false, jobs: "4")
      expect(written).to eq("project" => "Acme", "lane" => "quick", "frontend" => false, "jobs" => 4)
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
        .to match(["project: Acme\nlane: full\n", include("nothing was written", "Would write"), false, false])
    end
  end

  context "with a terminal" do
    let(:tty) { true }
    let(:answer) { "YES" }

    before do
      allow(prompt).to receive(:ask).with("Project name:", default: "acme-app").and_return("Acme")
      allow(prompt).to receive(:ask).with(/Plans to run at once/).and_return("3")
      allow(prompt).to receive(:select).with(/Default lane/, %w[full plan quick]).and_return("plan")
      allow(prompt).to receive(:select).with(/front end/, ["each plan decides", "YES", "NO"]).and_return("NO")
      allow(prompt).to receive(:select).with(/\AWrite /, %w[YES NO]).and_return(answer)
    end

    it "asks for each value and writes the answers" do
      run
      expect(written).to eq("project" => "Acme", "lane" => "plan", "frontend" => false, "jobs" => 3)
    end

    it "asks only for what no flag gave" do
      run(project: "Flagged", lane: "quick", frontend: true, jobs: "2")
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

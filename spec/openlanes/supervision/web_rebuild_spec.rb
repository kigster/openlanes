# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::WebRebuild do
  subject(:rebuild) { described_class.new(root:, host:, npm: -> { npm }, timeout: 300) }

  let(:root) { Dir.mktmpdir("web-rebuild") }
  # The project the factory runs in: OpenLanes itself unless an example says otherwise.
  let(:project) { Dir.mktmpdir("web-rebuild-project") }
  let(:justfile) { true }
  let(:config) { "project: openlanes\n" }
  let(:web) { File.join(root, "web") }
  let(:npm) { true }
  let(:spawner) { OpenLanes::Spawner::Fake.new(pids: [501]) }
  let(:clock) { OpenLanes::Clock::Fake.new }
  let(:status) { nil }
  let(:signals) { [] }
  let(:host) do
    OpenLanes::Supervision::Host.new(spawner:, waiter: ->(_) { status }, signaller: ->(*args) { signals << args }, clock:)
  end

  def exited(code) = instance_double(Process::Status, exitstatus: code, signaled?: false)

  before do
    FileUtils.mkdir_p(File.join(web, "dist"))
    File.write(File.join(web, "package.json"), "{}")
    File.write(File.join(web, "dist", "index.html"), "old page")
    File.write(File.join(project, "justfile"), "web-build:\n    cd web && npm run build\n") if justfile
    next unless config

    FileUtils.mkdir_p(File.join(project, ".openlanes"))
    File.write(File.join(project, ".openlanes", "config.yml"), config)
  end

  # The supervisor runs in the project root, and that is where the build looks.
  around { |example| Dir.chdir(project) { example.run } }

  after { [root, project].each { FileUtils.rm_rf(it) } }

  # The build is OpenLanes building its own page, so it runs only where the
  # project is OpenLanes: a justfile at its root and `project: openlanes`.
  describe "which project it builds for" do
    [
      [true,  "project: openlanes\n", true,  "a justfile and project: openlanes"],
      [true,  "project: OpenLanes\n", true,  "a justfile and the name in another case"],
      [false, "project: openlanes\n", false, "project: openlanes but no justfile"],
      [true,  "project: Demo App\n",  false, "a justfile but another project"],
      [true,  "jobs: 2\n",            false, "a justfile but no project named"],
      [true,  nil,                    false, "a justfile but no config file"],
      [false, "project: Demo App\n",  false, "neither"],
      [true,  "project: [\n",         false, "a config that cannot be read"]
    ].each do |with_justfile, yaml, builds, title|
      context "with #{title}" do
        let(:justfile) { with_justfile }
        let(:config) { yaml }

        it(builds ? "builds" : "builds nothing") { expect(rebuild.start.then { spawner.calls.size }).to eq(builds ? 1 : 0) }

        next if builds

        it "settles at once as skipped, and leaves the page as it was" do
          outcome = rebuild.start.poll
          expect([outcome.status, outcome.skipped?, File.read(File.join(web, "dist", "index.html"))]).to eq(["skipped", true, "old page"])
        end
      end
    end
  end

  it "runs npm run build in the gem's web/, in a group of its own, and never blocks" do
    rebuild.start
    aggregate_failures do
      expect(spawner.calls.map(&:argv)).to eq([%w[npm run build]])
      expect(spawner.calls.first.options).to include(chdir: web, pgroup: true)
      expect(rebuild.poll).to be_nil
    end
  end

  it "spawns once however often it is started" do
    rebuild.start.start
    expect(spawner.calls.size).to eq(1)
  end

  context "when the build succeeds" do
    let(:status) { exited(0) }

    it("says the page was rebuilt") { expect(rebuild.start.poll).to have_attributes(status: "ok", ok?: true) }
  end

  context "when the build fails" do
    let(:status) { exited(2) }

    it "says so and puts the old page back" do
      rebuild.start
      File.write(File.join(web, "dist", "index.html"), "half a page")
      outcome = rebuild.poll
      aggregate_failures do
        expect(outcome).to have_attributes(status: "failed", ok?: false)
        expect(outcome.message).to include("exit 2", "old page stays")
        expect(File.read(File.join(web, "dist", "index.html"))).to eq("old page")
      end
    end
  end

  context "when npm is not on PATH" do
    let(:npm) { false }

    it "starts nothing and says why" do
      outcome = rebuild.start.poll
      aggregate_failures do
        expect(outcome).to have_attributes(status: "no_npm")
        expect(spawner.calls).to be_empty
      end
    end
  end

  context "when the gem ships no page sources" do
    before { FileUtils.rm_f(File.join(web, "package.json")) }

    it "starts nothing and says why" do
      expect(rebuild.start.poll).to have_attributes(status: "no_sources", message: include("package.json is missing"))
    end
  end

  context "when the build runs past its time" do
    let(:reaped) { [] }
    let(:host) do
      OpenLanes::Supervision::Host.new(spawner:, waiter: ->(_) { reaped.shift }, signaller: ->(*args) { signals << args }, clock:)
    end

    before do
      rebuild.start
      File.write(File.join(web, "dist", "index.html"), "half a page")
      clock.advance(301)
    end

    it "kills its group once, and waits for it to end before settling (F2)" do
      aggregate_failures do
        expect([rebuild.poll, rebuild.poll]).to eq([nil, nil])
        expect(signals).to eq([["KILL", -501]])
      end
    end

    it "counts it a failure once the killed build is reaped, and puts the old page back" do
      rebuild.poll
      reaped << :gone
      aggregate_failures do
        expect(rebuild.poll).to have_attributes(status: "timeout", message: include("ran past 300 seconds"))
        expect(File.read(File.join(web, "dist", "index.html"))).to eq("old page")
      end
    end
  end

  # F1: nothing between Supervisor#tick and here rescues, so an error from
  # the file system has to come back as an outcome.
  describe "a web/ that cannot be used (F1)" do
    let(:dist) { File.join(web, "dist") }

    context "when the build cannot be spawned" do
      let(:spawner) do
        Class.new { def spawn(*, **) = raise(Errno::EACCES, "web") }.new
      end

      it "settles as failed, with the reason, and leaves the page alone" do
        outcome = rebuild.start.poll
        aggregate_failures do
          expect(outcome).to have_attributes(status: "failed", message: include("could not start", "Permission denied"))
          expect(File.read(File.join(dist, "index.html"))).to eq("old page")
        end
      end
    end

    context "when the old page cannot be copied aside" do
      before do
        File.write(File.join(dist, "secret.js"), "x")
        File.chmod(0o000, File.join(dist, "secret.js"))
      end

      after { File.chmod(0o644, File.join(dist, "secret.js")) }

      it "starts no build and settles as failed" do
        skip "root reads any file" if Process.uid.zero?
        outcome = rebuild.start.poll
        aggregate_failures do
          expect(outcome).to have_attributes(status: "failed", message: include("could not start"))
          expect(spawner.calls).to be_empty
        end
      end
    end

    context "when the old page cannot be put back after a failed build" do
      let(:status) { exited(1) }

      before do
        rebuild.start
        # An installed gem's web/ that this user may not write.
        FileUtils.rm_rf(dist)
        File.chmod(0o555, web)
      end

      after { File.chmod(0o755, web) }

      it "settles as failed and says the page could not be put back" do
        skip "root writes anywhere" if Process.uid.zero?
        expect(rebuild.poll).to have_attributes(status: "failed", message: include("exit 1", "could not be put back"))
      end
    end

    context "when the build's log cannot be read" do
      let(:status) { exited(1) }

      before do
        rebuild.start
        FileUtils.mkdir_p(spawner.calls.first.options.fetch(:out))
      end

      it "settles as failed instead of raising" do
        expect(rebuild.poll).to have_attributes(status: "failed", message: include("could not be read"))
      end
    end
  end

  describe "the build's log (F101)" do
    let(:status) { exited(2) }
    let(:log) { spawner.calls.first.options.fetch(:out) }

    it "is written in a directory only this user can use, not under a predictable name in tmp" do
      rebuild.start
      aggregate_failures do
        expect(File.dirname(log)).not_to eq(Dir.tmpdir)
        expect(File.stat(File.dirname(log)).mode & 0o777).to eq(0o700)
      end
    end

    it "is told in the reply and removed once the build has settled" do
      rebuild.start
      File.write(log, "error TS2304: Cannot find name 'x'\n")
      outcome = rebuild.poll
      aggregate_failures do
        expect(outcome.message).to include("Cannot find name 'x'")
        expect(File.exist?(File.dirname(log))).to be(false)
      end
    end
  end
end

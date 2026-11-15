# frozen_string_literal: true

# `/restart-web` end to end inside a Supervisor, with the real WebRebuild
# over a pretend gem root and a spawner that starts nothing (issue 253):
# whatever goes wrong in a restart, `openlanes start` outlives it.
RSpec.describe OpenLanes::Supervision::WebRestart do
  subject(:supervisor) do
    OpenLanes::Supervision::Supervisor.new(programs:, registration:, lifeline:, host:)
  end

  let(:root) { Dir.mktmpdir("web-restart") }
  let(:gem_root) { File.join(root, "gem") }
  let(:dist) { File.join(gem_root, "web", "dist") }
  let(:page) { File.join(dist, "index.html") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(File.join(root, "pids")) }
  let(:note) { File.join(dir.path, described_class::NOTE) }
  let(:registration) do
    OpenLanes::Supervision::Registration.new(draft: OpenLanes::Supervision::PidFile.new(role: "supervisor", pid: Process.pid, started: nil, root:),
      dir:,
      probe: instance_double(OpenLanes::Supervision::Probe, started: "x", verified?: false),
      title: OpenLanes::Supervision::Title.new(role: "supervisor", root:, setter: ->(_) {}))
  end
  let(:lifeline) { instance_double(OpenLanes::Supervision::Lifeline, env: {}, options: {}, cut: nil) }
  let(:spawner) { OpenLanes::Spawner::Fake.new(pids: (101..120).to_a) }
  let(:clock) { OpenLanes::Clock::Fake.new }
  let(:host) { OpenLanes::Supervision::Host.new(spawner:, waiter: ->(pid) { ends.delete(pid) }, signaller:, clock:) }
  let(:programs) do
    [OpenLanes::Supervision::Program.new(role: "engine", argv: %w[engine], essential: true),
     OpenLanes::Supervision::Program.new(role: "web", argv: %w[web])]
  end
  let(:ends) { {} }
  let(:signals) { [] }
  let(:stubborn) { [] }
  let(:signaller) do
    lambda do |signal, group|
      signals << [signal, -group]
      ends[-group] = exited(0) unless signal == "INT" && stubborn.include?(-group)
    end
  end
  let(:web) { supervisor.slots.last }
  # What the build comes to once it is seen running; nil leaves it running.
  let(:build_status) { exited(0) }
  let(:asked) { [] }
  let(:ended) { [] }
  let(:on_tick) do
    lambda do |s|
      asked << s.restart_web! if asked.empty?
      built
      s.stop! if spawned.count("web") == 2
    end
  end

  def exited(code) = instance_double(Process::Status, exitstatus: code, signaled?: false)
  def spawned = spawner.calls.map { it.argv.first }
  def build = spawner.calls.find { it.argv == %w[npm run build] }
  def build_pid = 101 + spawner.calls.index(build)

  # Ends the build, once, the tick after it was spawned.
  def built
    return if ended.any? || build.nil? || build_status.nil?

    ended << build_pid
    ends[build_pid] = build_status
  end

  before do
    FileUtils.mkdir_p(dist)
    File.write(File.join(gem_root, "web", "package.json"), "{}")
    File.write(page, "old page")
    allow(OpenLanes::Supervision::WebRebuild).to receive(:new).and_wrap_original do |original, **keywords|
      original.call(root: gem_root, npm: -> { true }, **keywords)
    end
    registration.claim
  end

  after { FileUtils.rm_rf(root) }

  context "when a failed build's log holds bytes the locale cannot read" do
    let(:build_status) { exited(1) }
    let(:on_tick) do
      lambda do |s|
        asked << s.restart_web! if asked.empty?
        File.binwrite(build.options.fetch(:out), "\xE2\x9C\x93 12 modules transformed.\n\xFF\xE2\x9C\x97 Build failed in 80ms\n") if build && ended.empty?
        built
        s.stop! if spawned.count("web") == 2
      end
    end

    # cron, systemd and Docker start `openlanes start` under LC_ALL=C.
    around do |example|
      external = Encoding.default_external
      verbose = $VERBOSE
      $VERBOSE = nil
      Encoding.default_external = Encoding::US_ASCII
      example.run
    ensure
      Encoding.default_external = external
      $VERBOSE = verbose
    end

    before { supervisor.call(&on_tick) }

    it "tells the log in the note instead of ending the factory" do
      told = JSON.parse(File.read(note, encoding: "UTF-8"))
      expect(told).to include("status" => "failed", "message" => include("exit 1", "✓ 12 modules transformed.", "✗ Build failed in 80ms"))
    end

    it("starts the web again on its old page") { expect([spawned, File.read(page)]).to eq([%w[engine web npm web], "old page"]) }
    it("removes the build's log") { expect(File.exist?(File.dirname(build.options.fetch(:out)))).to be(false) }
  end

  context "when the note cannot be written" do
    # A directory where the note goes: File.write raises EISDIR.
    before do
      FileUtils.mkdir_p(note)
      supervisor.call(&on_tick)
    end

    it("starts the web again all the same") { expect([spawned, web.held]).to eq([%w[engine web npm web], nil]) }
  end

  context "when a step raises what nothing expected" do
    let(:broken) { instance_double(OpenLanes::Supervision::WebRebuild, cancel: nil) }

    before do
      allow(broken).to receive(:start).and_raise(NoMethodError, "undefined method 'x'")
      allow(OpenLanes::Supervision::WebRebuild).to receive(:new).and_return(broken)
      supervisor.call(&on_tick)
    end

    it("gives the restart up and starts the web again") { expect([spawned, web.held]).to eq([%w[engine web web], nil]) }
    it("ends the build it had") { expect(broken).to have_received(:cancel) }
  end

  context "when the factory is stopped while the page builds" do
    let(:build_status) { nil }
    let(:on_tick) do
      lambda do |s|
        asked << s.restart_web! if asked.empty?
        next unless build

        # vite has emptied its out dir and is still building.
        FileUtils.rm_f(page)
        s.stop!
      end
    end

    before { supervisor.call(&on_tick) }

    it("kills the build's process group") { expect(signals).to include(["KILL", build_pid]) }
    it("reaps it") { expect(ends).not_to have_key(build_pid) }
    it("puts the old page back") { expect(File.read(page)).to eq("old page") }
    it("lets go of the web's slot") { expect(web.held).to be_nil }
    it("removes the build's log") { expect(File.exist?(File.dirname(build.options.fetch(:out)))).to be(false) }
    it("leaves no note for a later start to tell") { expect(File.exist?(note)).to be(false) }
  end

  context "when the web ignores INT" do
    let(:stubborn) { [102] }

    before { supervisor.call(&on_tick) }

    it("KILLs it once its grace has run out") { expect(signals.first(2)).to eq([["INT", 102], ["KILL", 102]]) }
    it("waited the shutdown's grace first") { expect(clock.monotonic).to be >= OpenLanes::Supervision::Supervisor::GRACE }
    it("then builds and starts the web again") { expect(spawned).to eq(%w[engine web npm web]) }
  end

  context "when an earlier supervisor left a note nobody took" do
    let(:seen) { [] }
    let(:on_tick) do
      lambda do |s|
        seen << File.exist?(note)
        s.stop!
      end
    end

    before do
      outcome = OpenLanes::Supervision::WebRebuild::Outcome.new(status: "ok", message: "the page was rebuilt")
      OpenLanes::Supervision::WebRestartNote.new(outcome:, at: Time.now).write(note)
      supervisor.call(&on_tick)
    end

    it("drops it as it starts, before any web can tell it") { expect(seen).to eq([false]) }
  end

  context "when the supervisor had given the web up" do
    let(:failed) { [] }
    let(:on_tick) do
      lambda do |s|
        ends[102] = exited(69) if web.pid == 102
        if web.given_up && asked.empty?
          failed << dir.read("supervisor").failed
          asked << s.restart_web!
        end
        built
        s.stop! if spawned.count("web") == 2
      end
    end

    before { supervisor.call(&on_tick) }

    it("takes it back") { expect([web.given_up, spawned]).to eq([nil, %w[engine web npm web]]) }

    it "stops listing it as failed in its PID file, which openlanes status reads" do
      expect([failed, registration.file.failed]).to eq([[{ "web" => "exited 69" }], {}])
    end
  end
end

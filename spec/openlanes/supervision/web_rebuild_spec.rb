# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::WebRebuild do
  subject(:rebuild) { described_class.new(root:, host:, npm: -> { npm }, timeout: 300) }

  let(:root) { Dir.mktmpdir("web-rebuild") }
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
  end

  after { FileUtils.rm_rf(root) }

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
    it "kills its group and counts it a failure" do
      rebuild.start
      clock.advance(301)
      aggregate_failures do
        expect(rebuild.poll).to have_attributes(status: "timeout")
        expect(signals).to eq([["KILL", -501]])
      end
    end
  end
end

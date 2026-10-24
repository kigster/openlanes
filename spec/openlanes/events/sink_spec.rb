# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Events::Sink do
  let(:home) { Dir.mktmpdir("events") }
  let(:dir) { File.join(home, "nested", "events") }
  let(:warnings) { [] }
  let(:sink) { described_class.new(dir:, node: "n1", checkout: "c1", project: "demo", warn: ->(w) { warnings << w }) }

  after { FileUtils.rm_rf(home) }

  it "creates the directory on first write and appends one line per event" do
    run = sink.with(run: "r1")
    run.record(:run_started, jobs: 2)
    run.record(:agent_started, plan: "020.01", round: 1, agent: "luke-backend", invocation_start: Time.utc(2026, 10, 16))

    events = OpenLanes::Events::Log.new(dir:).events
    expect(File.basename(sink.path)).to eq("n1.jsonl")
    expect(events.map(&:kind)).to eq(%w[run_started agent_started])
    expect(events.map(&:run).uniq).to eq(["r1"])
    expect(events.last.payload).to eq("round" => 1, "invocation_start" => "2026-10-16T00:00:00.000Z")
  end

  it "gives a replayed invocation the same event id, so the reader keeps one" do
    2.times { sink.record(:agent_started, plan: "020.01", round: 1, agent: "a", invocation_start: "t0") }

    expect(File.readlines(sink.path).size).to eq(2)
    expect(OpenLanes::Events::Log.new(dir:).events.size).to eq(1)
  end

  it "writes with no Redis at all, and a raising store changes nothing" do
    allow(OpenLanes::Live::Store).to receive(:new).and_raise(OpenLanes::Live::Unavailable, "redis down")

    expect(sink.record(:run_started, jobs: 1)).to be_a(OpenLanes::Events::Event)
    expect(File.readlines(sink.path).size).to eq(1)
  end

  it "warns instead of raising when the directory cannot be written" do
    File.write(File.join(home, "nested"), "a file, not a directory")

    expect(sink.record(:run_started, jobs: 1)).to be_nil
    expect(warnings.join).to include("run_started not written")
  end

  it "warns instead of raising when the event cannot be built" do
    expect(sink.record(:run_started, prompt: "secret")).to be_nil
    expect(warnings.join).to include("run_started not recorded")
    expect(File).not_to exist(sink.path)
  end

  describe OpenLanes::Events::NullSink do
    it "creates no file or directory and answers every call" do
      null = described_class.new.with(run: "r1")
      null.record(:run_started, jobs: 1)
      null.emit(nil)

      expect(null.enabled?).to be(false)
      expect(null.run).to be_nil
      expect(Dir.children(home)).to be_empty
    end
  end

  describe "OpenLanes::Events.emitter" do
    let(:root) { Dir.mktmpdir("proj") }
    let(:node) { OpenLanes::Live::Node.current(root:, user: "u", host: "h", ip: nil) }

    after { FileUtils.rm_rf(root) }

    it "is the null sink when the config key is absent" do
      emitter = OpenLanes::Events.emitter(root:, config: OpenLanes::Config.new, node:)

      expect(emitter).to be_a(OpenLanes::Events::NullSink)
    end

    it "is a sink at the configured directory when enabled" do
      config = OpenLanes::Config.new(events_enabled: true, events_dir: dir)
      emitter = OpenLanes::Events.emitter(root:, config:, node:)

      expect(emitter).to have_attributes(dir:, node: node.id, checkout: node.checkout_id, project: File.basename(root))
      expect(OpenLanes::Events.dir(root:, config:)).to eq(dir)
    end
  end
end

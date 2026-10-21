# frozen_string_literal: true

require "json_schemer"

# B2: the writer appends, fsyncs, mirrors best-effort, and stays out of .plans.
RSpec.describe OpenLanes::Engine::EventJournal do
  subject(:journal) { described_class.new(root:, run_id: "r1", node: "mbp:abc123", bus:, channel: "openlanes:x:journal") }

  let(:root) { Dir.mktmpdir("openlanes-journal-root") }
  let(:bus) { nil }
  let(:schema) { JSONSchemer.schema(Pathname.new(described_class::SCHEMA_PATH)) }
  let(:lines) { File.readlines(journal.path).map { JSON.parse(it) } }

  after do
    journal.close
    FileUtils.rm_rf(root)
  end

  it "lands under the runtime directory, outside .plans" do
    expect(journal.path).to eq(File.join(OpenLanes::Runtime.journal_dir(root:), "r1.ndjson"))
    expect(journal.path).not_to include(".plans")
  end

  it "writes one schema-valid line per append, flushed and fsync'd" do
    file = journal.instance_variable_get(:@file)
    allow(file).to receive(:fsync).and_call_original
    journal.append(:run_started, jobs: 1, isolation: "shared")
    journal.append(:transition, plan: "039.00", from: "building", to: "review", event: "review")
    expect(file).to have_received(:fsync).twice
    expect(lines.map { it["kind"] }).to eq(%w[run_started transition])
    expect(lines.flat_map { schema.validate(it).map { |e| e["error"] } }).to eq([])
  end

  it "returns the event it wrote" do
    expect(journal.append(:run_ended, reason: "done")).to include("v" => 1, "seq" => 1, "kind" => "run_ended", "reason" => "done")
  end

  it "refuses a kind the schema does not know" do
    expect { journal.append(:teleported) }.to raise_error(ArgumentError, /teleported/)
  end

  it "numbers lines without gaps or repeats under concurrent appends" do
    Array.new(8) { |t| Thread.new { 25.times { journal.append(:agent_offset, plan: "039.00", agent: "a#{t}", offset: it) } } }.each(&:join)
    expect(lines.map { it["seq"] }).to eq((1..200).to_a)
  end

  it "carries on numbering when the same run's file is reopened" do
    journal.append(:run_started)
    journal.close
    again = described_class.new(root:, run_id: "r1", node: "n")
    File.open(again.path, "a") { it.write("{\"torn") }
    expect(again.append(:run_ended)["seq"]).to eq(2)
    again.close
  end

  it "starts a fresh line after a torn tail, so the next event survives a replay" do
    journal.append(:run_started)
    journal.close
    File.open(journal.path, "a") { it.write("{\"v\":1,\"seq\":2,\"run_i") }
    again = described_class.new(root:, run_id: "r1", node: "n")
    again.append(:run_ended, reason: "quit")
    again.close
    picture = OpenLanes::Engine::EventJournal::Replay.call(again.path)
    expect([picture.torn, picture.seq, picture.running?]).to eq([1, 2, false])
  end

  context "with a bus" do
    let(:bus) { instance_double(OpenLanes::Live::EventBus::Base, publish: 1) }

    it "mirrors each line on the journal channel after writing it" do
      event = journal.append(:run_started)
      expect(bus).to have_received(:publish).with("openlanes:x:journal", JSON.generate(event))
    end
  end

  context "with a bus that is down" do
    let(:bus) { instance_double(OpenLanes::Live::EventBus::Base) }

    before do
      allow(bus).to receive(:publish).and_raise(Errno::ECONNREFUSED)
      allow(OpenLanes::UI).to receive(:log)
    end

    it "keeps every line on disk and reports the outage once" do
      journal.append(:run_started)
      journal.append(:run_ended)
      expect(lines.map { it["kind"] }).to eq(%w[run_started run_ended])
      expect(OpenLanes::UI).to have_received(:log).once
    end
  end

  describe ".latest" do
    it "names the newest journal under the root" do
      journal.append(:run_started)
      expect(described_class.latest(root:)).to eq(journal.path)
    end
  end

  describe ".run_id" do
    it "is sortable by time and unique" do
      clock = class_double(Time, now: Time.utc(2026, 10, 21, 9, 8, 7))
      expect(described_class.run_id(clock:)).to match(/\A20261021-090807-\h{6}\z/)
    end
  end
end

# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::RestartRequest do
  subject(:request) { described_class.new(dir:, probe:, host:) }

  let(:root) { Dir.mktmpdir("restart-request") }
  let(:dir) { OpenLanes::Supervision::PidDir.new(File.join(root, "pids")) }
  let(:probe) { instance_double(OpenLanes::Supervision::Probe, verified?: verified) }
  let(:verified) { true }
  let(:signals) { [] }
  let(:host) { OpenLanes::Supervision::Host.new(spawner: nil, waiter: nil, signaller: ->(*args) { signals << args }, clock: nil) }

  def register(url:) = dir.write(OpenLanes::Supervision::PidFile.new(role: "supervisor", pid: 777, started: "x", root:, url:))

  after { FileUtils.rm_rf(root) }

  it "sends USR2 to a live supervisor that serves a control room" do
    register(url: "http://127.0.0.1:4000")
    aggregate_failures do
      expect(request.call).to eq(777)
      expect(signals).to eq([["USR2", 777]])
    end
  end

  it "sends nothing when no supervisor runs" do
    expect([request.call, signals]).to eq([nil, []])
  end

  it "sends nothing to a supervisor started with --no-web" do
    register(url: nil)
    expect([request.call, signals]).to eq([nil, []])
  end

  context "when the PID file is a crash's leftover" do
    let(:verified) { false }

    it "sends nothing" do
      register(url: "http://127.0.0.1:4000")
      expect([request.call, signals]).to eq([nil, []])
    end
  end
end

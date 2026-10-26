# frozen_string_literal: true

require "rbconfig"
require "socket"

# Real processes on real ports, through the real supervisor: what is under
# test is that the app is up while the block runs and gone afterwards.
RSpec.describe OpenLanes::Engine::Verification::AppSession do
  let(:dir) { File.realpath(Dir.mktmpdir("openlanes-app-session")) }
  let(:registry) { OpenLanes::Apps::Ports.new(path: File.join(dir, "ports.json")) }
  let(:server) { File.expand_path("../../../fixtures/apps/servers/server.rb", __dir__) }
  let(:factory) do
    ->(**options) { OpenLanes::Apps::Supervisor.new(**options, registry:, ready_timeout: 10, poll: 0.05) }
  end
  let!(:children_before) { OpenLanes::Execution::Child.live }

  after { FileUtils.rm_rf(dir) }

  def session(definition) = described_class.new(definition:, root: dir, plan: "014.00", branch: "kig/014.00-x", supervisor_factory: factory)

  def process(name, start, **) = OpenLanes::Apps::ProcessSpec.new(name:, start:, **)

  def app(*processes) = OpenLanes::Apps::Definition.new(kind: "web", processes:)

  def answering?(port)
    Socket.tcp("127.0.0.1", port, connect_timeout: 0.2).close
    true
  rescue SystemCallError
    false
  end

  def alive_children = (OpenLanes::Execution::Child.live - children_before).select(&:alive?)

  it "runs the block with every process ready, and stops them all afterwards" do
    definition = app(process("api", "#{RbConfig.ruby} #{server} --name api --port-env PORT_API"),
      process("web", "#{RbConfig.ruby} #{server} --name web --port-env PORT_WEB", preview: true))
    seen = nil

    value = session(definition).around do |statuses|
      seen = statuses.map { [it.process, it.state, answering?(it.port)] }
      :agent_ran
    end

    aggregate_failures do
      expect(value).to eq(:agent_ran)
      expect(seen).to eq([["api", "ready", true], ["web", "ready", true]])
      expect(alive_children).to be_empty
      expect(registry.entries).to be_empty
    end
  end

  it "stops the app even when the block raises" do
    definition = app(process("web", "#{RbConfig.ruby} #{server} --name web --port-env PORT_WEB"))

    expect { session(definition).around { raise "agent crashed" } }.to raise_error("agent crashed")
    expect([alive_children, registry.entries]).to eq([[], {}])
  end

  it "fails without calling the block when a process never becomes ready, with its last 20 lines" do
    definition = app(process("web", "for i in $(seq 1 30); do echo line $i; done; exit 3"))
    called = false

    failed = session(definition).around { called = true }

    aggregate_failures do
      expect(called).to be(false)
      expect(failed).to be_a(described_class::Failed)
      expect(failed.tail).to eq((11..30).map { "line #{it}" })
      expect(failed.to_markdown).to start_with("the app does not start: web exited with status 3")
      expect(failed.to_markdown).to include("The last 20 lines web printed:", "line 11\n", "line 30\n```")
      expect(alive_children).to be_empty
    end
  end

  it "starts nothing and yields no statuses when the project declares no app" do
    expect(session(nil).around { it }).to eq([])
  end

  describe ".note" do
    it "tells verifier each process's port and URL" do
      definition = app(process("api", "x"), process("web", "y", preview: true))
      statuses = [
        OpenLanes::Apps::Status.new(plan: "014.00", branch: "b", process: "api", state: "ready", port: 11_200),
        OpenLanes::Apps::Status.new(plan: "014.00", branch: "b", process: "web", state: "ready", port: 11_201, preview: true)
      ]

      expect(described_class.note(statuses, definition))
        .to include("| api | `PORT_API=11200` | http://127.0.0.1:11200/ |  |", "| web | `PORT_WEB=11201` | http://127.0.0.1:11201/ | yes |")
    end

    it "says to verify through the shell when there is no app" do
      expect(described_class.note([], nil)).to include("through the shell (M11)")
    end
  end
end

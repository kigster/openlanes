# frozen_string_literal: true

# B9 in plan 041: a verifier's preview app died with the engine that started
# it, so the verifier is stopped rather than taken back, and left to
# Recovery::Stranded. The end-to-end case is spec/integration/reattach_spec.rb.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  subject(:dispatcher) { described_class.new(runner:, state:) }

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:,
      executor:     instance_double(OpenLanes::Execution::Executor),
      verification: instance_double(OpenLanes::Engine::Verification::Driver))
  end
  let(:state) { instance_double(OpenLanes::Engine::StateFile) }
  let(:verifier) { OpenLanes::Agents.find("backend-coder").with(phase: OpenLanes::Engine::Verification::PHASE) }
  let(:process) { { "pid" => 4242 } }
  let(:found) do
    OpenLanes::Engine::Recovery::Reattach::Found.new(subject: tree.subjects.first,
      agent: verifier,
      round: 1,
      from: :verifying,
      restart: { "process" => process })
  end
  let(:agent_process) { instance_double(OpenLanes::Execution::AgentProcess, terminate: nil, wait: nil) }
  let(:taken) { dispatcher.send(:reattach) }

  before do
    plans { |t| t.plan "001.00", :new, "check", files: { "spec.md" => spec_body } }
    allow(OpenLanes::Engine::Recovery::Reattach).to receive(:new).and_return(instance_double(OpenLanes::Engine::Recovery::Reattach, call: [found]))
    allow(OpenLanes::Execution::AgentProcess).to receive(:attach).with(process).and_return(agent_process)
  end

  describe "a verifier a dead engine left" do
    before { taken }

    it("is not taken back") { expect(taken).to be_empty }
    it("is stopped, and waited for") { expect(agent_process).to have_received(:wait) }
    it("by TERM") { expect(agent_process).to have_received(:terminate) }
  end

  context "without a state file" do
    let(:state) { nil }

    it("takes nothing back") { expect(taken).to be_empty }
    it("looks for nothing") { taken && expect(OpenLanes::Engine::Recovery::Reattach).not_to(have_received(:new)) }
  end
end

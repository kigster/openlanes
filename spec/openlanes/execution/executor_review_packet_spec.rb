# frozen_string_literal: true

# Plan 060.00, item 1: the executor asks for a round's packet once per
# reviewer it starts and puts it at the head of that reviewer's prompt. The
# fake spawn keeps every argv, so nothing here starts `claude` or `gh`.
RSpec.describe OpenLanes::Execution::Executor, :tree do
  let(:executor) { described_class.new(root:, spawn:, trace_dir: traces, packets:, **options) }
  let(:options) { {} }
  let(:root) { File.dirname(plans_root) }
  let(:traces) { File.join(root, "traces") }
  let(:packet) { "# Review packet\n\n<diff pr=\"4\">\n+x\n</diff>\n\n---\n\n" }
  let(:asked) { [] }
  let(:packets) { ->(subject) { asked << subject.feature.ordinal.to_s and packet } }
  let(:agent) { OpenLanes::Agents.find("staff-reviewer") }
  let(:plan) do
    plans { |t| t.plan "001.00", :in_review, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end
  let(:spawned) { [] }
  let(:spawn) do
    lambda do |argv, **|
      spawned << argv
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      instance_double(OpenLanes::Execution::Child, pid: 101, alive?: false, kill: nil, terminate: nil, wait: status, each_chunk: nil)
    end
  end

  after { OpenLanes::Execution::Control.reset! }

  def prompt_of(who)
    executor.call(who, plan, handle: described_class::Handle.new)
    spawned.last.find { it.include?("## This invocation") }
  end

  it "opens a reviewer's prompt with the round's packet" do
    expect(prompt_of(agent)).to start_with(packet)
    expect(asked).to eq(["001.00"])
  end

  it "gives every reviewer of the round the same packet" do
    others = %w[security-reviewer design-reviewer].map { prompt_of(OpenLanes::Agents.find(it)) }

    expect(others).to all(start_with(packet))
  end

  it "asks for none for an agent that is not reviewing" do
    expect(prompt_of(OpenLanes::Agents.find("backend-coder"))).not_to include("# Review packet")
    expect(asked).to be_empty
  end

  context "without a packet builder" do
    let(:packets) { nil }

    it "starts the reviewer on its own definition, as before" do
      expect(prompt_of(agent)).to start_with(agent.prompt)
    end
  end

  context "when the packet cannot be built" do
    let(:packets) { ->(_) { raise OpenLanes::Error, "gh is signed out" } }

    it "still starts the reviewer, without one" do
      expect(prompt_of(agent)).to start_with(agent.prompt)
    end
  end

  context "when the run is a dry run" do
    let(:options) { { dry_run: true } }

    it "fetches nothing" do
      executor.call(agent, plan, handle: described_class::Handle.new)

      expect(asked).to be_empty
    end
  end
end

# frozen_string_literal: true

RSpec.describe "The live controls on one invocation" do
  # What the live run adds to one invocation: the adapter's environment on the
  # child, a model a person chose, and the word HOLD.
  describe OpenLanes::Execution::Executor, :tree do
    subject(:executor) { described_class.new(root:, spawn:, trace_dir: traces) }

    let(:root) { File.dirname(plans_root) }
    let(:traces) { File.join(root, "traces") }
    let(:spawned) { [] }
    let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
    let(:child) { instance_double(OpenLanes::Execution::Child, pid: 7, alive?: false, kill: nil, terminate: nil, wait: status, each_chunk: nil) }
    let(:spawn) do
      lambda { |argv, chdir:, env:|
        spawned << [argv, chdir, env]
        child
      }
    end
    let(:agent) { OpenLanes::Agents.find("luke-backend") }
    let(:plan) do
      plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
      OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
    end

    it "starts claude with its autocompact threshold in the environment (W28)" do
      executor.call(agent, plan)
      expect(spawned.first.last).to eq("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" => "40")
    end

    context "when a person chose a model for the agent on this plan" do
      before { executor.prefer_model("001.00", "luke-backend", "claude-haiku-5-5") }

      it "runs the agent on it" do
        expect(executor.profile_for(agent, plan).model).to eq("claude-haiku-5-5")
      end

      it "goes back to the agent's own once the choice is forgotten" do
        executor.prefer_model("001.00", "luke-backend", nil)
        expect(executor.profile_for(agent, plan).model).to eq(agent.model)
      end

      context "with run --model typed too" do
        subject(:executor) { described_class.new(root:, spawn:, model: "sonnet") }

        it "lets the person's later choice win" do
          expect(executor.profile_for(agent, plan).model).to eq("claude-haiku-5-5")
        end
      end
    end
  end

  describe OpenLanes::Execution::Child do
    subject(:child) { described_class.spawn(["ruby", "-e", "print ENV['OPENLANES_PROBE']"], env: { "OPENLANES_PROBE" => "40" }) }

    let(:out) { +"" }

    it "adds the adapter's variables to the child's environment" do
      child.each_chunk { out << it }
      child.wait
      expect(out).to eq("40")
    end
  end

  describe OpenLanes::Execution::Prompt, :tree do
    def prompt_for(name)
      agent = OpenLanes::Agents.find(name)
      described_class.new(agent:,
        subject: plan,
        root: "/repo",
        profile: OpenLanes::Agents::Profile.resolve(agent),
        control: "/tmp/control-001").to_s
    end

    let(:plan) do
      plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
      OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
    end

    it "explains HOLD beside the other control words" do
      expect(prompt_for("luke-backend")).to include("HOLD means a person wants to say something to you", "mail read --dir")
    end

    # `/compact` is the caller's command; an agent told to run it cannot.
    it "asks no agent to compact itself" do
      expect(prompt_for("luke-backend")).not_to include("/compact")
    end

    it "tells an agent that writes blocked.md how to mark a yes/no question (W30)" do
      expect(prompt_for("luke-backend")).to include("yes/no questions", "    #{OpenLanes::Live::Snapshot::YES_NO_MARK}")
    end

    it "leaves that out for the agent that drains blocked.md" do
      expect(prompt_for("lando-broker")).not_to include("yes/no questions")
    end
  end

  describe OpenLanes::Execution::Control do
    it "maps each word a person may send to one agent" do
      expect(described_class::WORDS).to eq("hold" => "HOLD", "wrap_up" => "WRAP_UP", "stop" => "STOP")
    end
  end
end

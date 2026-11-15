# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::CompactReply do
  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:broken) { instance_double(Process::Status, success?: false, exitstatus: 2) }

  def transcript(compacted: { "pre_tokens" => 9000, "post_tokens" => 800 }, failed: false, error: nil)
    instance_double(OpenLanes::Execution::Transcript, compacted:, failed?: failed, error:, plain: ["nope"])
  end

  it "finds nothing wrong with a /compact that compacted" do
    expect(described_class.failure(ok, transcript)).to be_nil
  end

  it "names the exit of one that failed" do
    expect(described_class.failure(broken, transcript)).to eq("/compact exited 2: nope")
  end

  it "names the error one reported" do
    expect(described_class.failure(ok, transcript(failed: true, error: "boom"))).to eq("/compact reported: boom")
  end

  it "says when it ran but did not compact" do
    expect(described_class.failure(ok, transcript(compacted: nil))).to eq("/compact did not compact: nope")
  end

  describe ".note" do
    let(:agent) { OpenLanes::Agents.find("backend-coder") }
    let(:sessions) { instance_double(OpenLanes::Execution::Executor::Sessions, previous: transcript) }
    let(:attempt) do
      OpenLanes::Execution::Executor::Attempt.new(agent:, subject: nil, root: "/r", profile: nil, trace: nil, handle: nil, sessions:)
    end

    it "says how far it compacted, and on what it carries on when a model was asked for" do
      expect(described_class.note(attempt, "sonnet", OpenLanes::Execution::Executor::Compaction.new(model: "sonnet")))
        .to eq("backend-coder compacted from 9000 to 800 tokens and carries on on sonnet")
    end

    it "names no model when none was asked for" do
      expect(described_class.note(attempt, "opus", OpenLanes::Execution::Executor::Compaction.new))
        .to eq("backend-coder compacted from 9000 to 800 tokens and carries on")
    end
  end
end

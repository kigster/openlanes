# frozen_string_literal: true

# M2: the journal is read out of the agent's own output, whichever CLI ran
# it, and the previous round's goes into the next round's prompt.
RSpec.describe "the agent journal, read from the stream and replayed in the prompt" do
  def entry(**fields) = JSON.generate(fields)

  describe OpenLanes::Execution::Transcript do
    subject(:transcript) { described_class.new }

    def assistant(body, parent: nil) = "#{{ type: "assistant", parent_tool_use_id: parent, message: { content: [{ type: "text", text: body }] } }.to_json}\n"

    it "keeps the agent's entries, in order, and not a sub-agent's" do
      transcript.push(assistant("ok\n#{entry(kind: "todo", text: "U1")}"))
      transcript.push(assistant(entry(kind: "note", text: "mine, not yours"), parent: "toolu_1"))
      transcript.push(assistant(entry(kind: "done", text: "U1")))

      expect(transcript.journal.map(&:kind)).to eq(%w[todo done])
    end
  end

  describe OpenLanes::Adapters::Stream do
    subject(:stream) { described_class.new }

    it "keeps entries from whole messages, not from their deltas" do
      [{ type: "item.delta", text: entry(kind: "note", text: "half") },
       { type: "item.completed", item: { type: "agent_message", text: entry(kind: "decision", text: "whole") } }]
        .each { stream.push("#{JSON.generate(it)}\n") }

      expect(stream.journal.map(&:text)).to eq(["whole"])
    end
  end

  describe OpenLanes::Execution::Executor, :tree do
    subject(:executor) { described_class.new(root:, spawn:) }

    let(:root) { File.dirname(plans_root) }
    let(:agent) { OpenLanes::Agents::Registry.new.find("luke-backend") }
    let(:handle) { described_class::Handle.new }
    let(:printed) { "#{{ type: "assistant", message: { content: [{ type: "text", text: entry(kind: "decision", text: "kept") }] } }.to_json}\n" }
    let(:child) do
      double = instance_double(OpenLanes::Execution::Child,
        pid:       4242,
        alive?:    true,
        kill:      nil,
        terminate: nil,
        wait:      instance_double(Process::Status, success?: false))
      allow(double).to receive(:each_chunk) do |&block|
        block.call(printed)
        handle.kill!(grace: 0)
      end
      double
    end
    let(:spawn) { ->(_argv, **) { child } }
    let(:subject_plan) { OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first }

    let(:traces) { Dir.mktmpdir("journal-traces") }

    before do
      stub_const("OpenLanes::Execution::Executor::TRACE_DIR", traces)
      plans { |t| t.plan "001.00", :building, "work", files: { "spec.md" => spec_body, "plan.md" => "## U1" } }
    end

    after do
      OpenLanes::Execution::Control.reset!
      FileUtils.rm_rf(traces)
    end

    it "still holds what a killed agent printed, for the dispatcher to write" do
      executor.call(agent, subject_plan, handle:)

      expect(handle.journal.map(&:text)).to eq(["kept"])
    end

    def prompt(round, resume: nil) = executor.invocation(agent, subject_plan, round:, resume:).join(" ")

    context "when the previous round kept a journal" do
      before do
        OpenLanes::Plans::PlanState.for(subject_plan.feature.path)
                                   .journal!(agent: "luke-backend",
                                     round: 1,
                                     entries: [OpenLanes::Plans::Journal::Entry.new(kind: "decision", text: "Redis")])
      end

      it "puts round n's journal into round n+1's prompt" do
        expect(prompt(2)).to include("Your journal from round 1").and include("#1 decision: Redis")
      end

      it "puts it there when the session is resumed, too" do
        expect(prompt(2, resume: "sess-1")).to include("#1 decision: Redis")
      end

      it "shows no previous journal to round 1" do
        expect(prompt(1)).not_to include("Your journal from round")
      end
    end

    it "tells every agent, reviewers and builders alike, how to keep the journal" do
      reviewer = OpenLanes::Agents::Registry.new.find("hansolo-reviewer")
      texts = [agent, reviewer].map { executor.invocation(it, subject_plan).join(" ") }

      expect(texts).to all(include("## Your journal - print it as you go").and(include('"overrides":3')))
    end
  end
end

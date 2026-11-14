# frozen_string_literal: true

# The unblocker interviewing, with `claude` replaced at the spawn seam by a
# fake that plays back a stream-json result. Nothing here starts a process.
RSpec.describe OpenLanes::Live::Interview::Operator, :tree do
  subject(:operator) { described_class.new(root: plans_root, plans_dir: plans_root, spawn:) }

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:interview) { OpenLanes::Live::Interview.new(store:, keys:, plan: "002.00", number: 1) }
  let(:question) { { kind: "question", text: "Should the branch be rebased?", options: [{ label: "yes", recommended: true }, { label: "no", recommended: false }] } }
  let(:results) { [JSON.generate(turns: [question])] }
  let(:spawned) { [] }
  let(:spawn) do
    lambda do |argv, chdir:, env:|
      spawned << { argv:, chdir:, env: }
      result = results.fetch(spawned.size - 1)
      child = instance_double(OpenLanes::Execution::Child, pid: 1, terminate: nil, wait: instance_double(Process::Status, success?: true, exitstatus: 0))
      allow(child).to receive(:each_chunk).and_yield("#{JSON.generate(type: "result", result:, is_error: false)}\n")
      child
    end
  end

  before do
    plans do |t|
      t.plan "002.00", :blocked, "rebase", files: { "spec.md" => "# Spec\n", "blocked.md" => "# Blocked\n\n## B1 Rebase\n\nShould I rebase?\n\na) yes (Recommended)\nb) no\n" }
    end
  end

  it "turns the model's JSON into checked turns, each with an id of its own" do
    turns = interview.reply(operator)
    expect(turns.map { [it.from, it.kind] }).to eq([%w[unblocker question]])
    expect(turns.first.id).to match(/\Au[[:alnum:]]{12}\z/)
  end

  it "briefs the model with the question, the rules and the conversation" do
    interview.reply(operator)
    prompt = spawned.first[:argv].join(" ")
    expect(prompt).to include("Should I rebase?", "Never reject", "Nothing yet")
  end

  context "when the model uses a bare label" do
    let(:results) { [JSON.generate(turns: [question.merge(text: "Is B1 settled?")]), JSON.generate(turns: [question])] }

    it "asks it to say it again, and shows only the rephrased turn" do
      expect(interview.reply(operator).map(&:text)).to eq(["Should the branch be rebased?"])
      expect(spawned.last[:argv].join(" ")).to include("Rephrase", "B1 is a bare label")
    end
  end

  context "when the model fails twice" do
    let(:results) { ["not json", "still not"] }

    it "asks a clarifying question rather than refusing anything" do
      expect(interview.reply(operator).map { [it.kind, it.text] }).to eq([["text", described_class::FALLBACK]])
    end
  end

  it "answers for a plan that is not there in plain words, through the interview" do
    other = OpenLanes::Live::Interview.new(store:, keys:, plan: "099.00", number: 1)
    expect(other.reply(operator).first.text).to include("there is no plan 099.00", "answer buttons still work")
  end
end

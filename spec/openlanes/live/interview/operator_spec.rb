# frozen_string_literal: true

# The unblocker interviewing, with `claude` replaced at the spawn seam by a
# fake that plays back a stream-json result. Nothing here starts a process.
RSpec.describe OpenLanes::Live::Interview::Operator, :tree do
  subject(:operator) { described_class.new(root: plans_root, plans_dir: plans_root, spawn:, agent:) }

  let(:agent) { OpenLanes::Agents.find("unblocker") }
  let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failed) { false }

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
      child = instance_double(OpenLanes::Execution::Child, pid: 1, terminate: nil, wait: status)
      allow(child).to receive(:each_chunk).and_yield("#{JSON.generate(type: "result", result:, is_error: failed)}\n")
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

  # Issue 252: none of these may reach the page as Ruby's own words.
  {
    "options as words"         => { turns: [{ kind: "question", text: "Rebase?", options: %w[yes no] }] },
    "a turn that is a string"  => { turns: ["Should the branch be rebased?"] },
    "turns that are no list"   => { turns: "Should the branch be rebased?" },
    "a reply that is a list"   => [{ kind: "text", text: "hi" }],
    "a reply holding no turns" => { turns: [] }
  }.each do |what, reply|
    context "when the model writes #{what}" do
      let(:results) { [JSON.generate(reply), JSON.generate(turns: [question])] }

      it "asks it to say it again, as for any output it cannot draw" do
        expect(interview.reply(operator).map(&:text)).to eq(["Should the branch be rebased?"])
        expect(spawned.last[:argv].join(" ")).to include("Rephrase")
      end
    end
  end

  # Issue 252: a usage limit was shown as a clarifying question, after a second run.
  context "when the run reports an error as its result" do
    let(:results) { ["Claude usage limit reached. Your limit will reset at 5pm."] }
    let(:failed) { true }

    it "says what failed, once, and does not ask the model to rephrase" do
      said = interview.reply(operator)
      aggregate_failures do
        expect(said.map(&:kind)).to eq(%w[text])
        expect(said.first.text).to include("could not go on", "reported: Claude usage limit reached", "answer buttons still work")
        expect(spawned.size).to eq(1)
      end
    end

    it "raises, for whoever calls it without the interview" do
      expect { operator.call(interview) }.to raise_error(described_class::Failed, /usage limit/)
    end
  end

  context "when the run exits non-zero" do
    let(:results) { [JSON.generate(turns: [question])] }
    let(:status) { instance_double(Process::Status, success?: false, exitstatus: 3) }

    it "does not take what it printed for an answer" do
      expect(interview.reply(operator).first.text).to include("exited 3")
      expect(spawned.size).to eq(1)
    end
  end

  context "when the run takes too long" do
    let(:agent) { OpenLanes::Agents.find("unblocker").with(timeout: 0.1) }
    let(:spawn) do
      lambda do |argv, chdir:, env:|
        spawned << { argv:, chdir:, env: }
        ended = false
        child = instance_double(OpenLanes::Execution::Child, pid: 1, wait: instance_double(Process::Status, success?: false, exitstatus: nil))
        allow(child).to receive(:terminate) { ended = true }
        allow(child).to receive(:each_chunk) { sleep 0.01 until ended }
        child
      end
    end

    it "is ended, and the person told why" do
      expect(interview.reply(operator).first.text).to include("took longer than 0.1 seconds")
      expect(spawned.size).to eq(1)
    end
  end

  it "never gives one run longer than the interview is held for" do
    slow = described_class.new(root: plans_root, plans_dir: plans_root, spawn:, agent: agent.with(timeout: 3600))
    expect(slow.send(:timeout) * 2).to be < OpenLanes::Live::Interview::BUSY
    expect(described_class.new(root: plans_root, plans_dir: plans_root, spawn:, agent: agent.with(timeout: nil)).send(:timeout))
      .to eq(described_class::TIMEOUT)
  end

  it "answers for a plan that is not there in plain words, through the interview" do
    other = OpenLanes::Live::Interview.new(store:, keys:, plan: "099.00", number: 1)
    expect(other.reply(operator).first.text).to include("there is no plan 099.00", "answer buttons still work")
  end
end

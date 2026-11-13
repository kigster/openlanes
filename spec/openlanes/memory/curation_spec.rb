# frozen_string_literal: true

RSpec.describe OpenLanes::Memory::Curation, :tree do
  subject(:curation) { described_class.new(executor:, agent:, root:, answer: ->(_trace) { said }) }

  let(:root) { File.dirname(plans_root) }
  let(:agent) { OpenLanes::Agents.find("curator") }
  let(:plan) { OpenLanes::Plans::Tree.new(dir: plans_root).find("002.00") }
  let(:result) { instance_double(OpenLanes::Execution::Executor::Result, ok: true, note: "Completed") }
  let(:executor) do
    lambda do |_agent, _subject, root:, handle:|
      handle.trace = File.join(root, "trace.ndjson")
      result
    end
  end
  let(:lesson) do
    JSON.generate("lesson" => { "slug" => "flaky-redis-specs", "title" => "Run the Redis outage specs alone", "applies_to" => ["build"],
                                "kind" => "pitfall", "finding" => "two rounds lost to a flapping spec", "body" => "They race on one client." })
  end
  let(:said) { "One lesson.\n#{lesson}\n{\"lesson\": 3}\n" }

  before { plans { |t| t.plan "002.00", :rejected, "rebase" } }

  it "files what the curator proposed under the plan it read, and reports what it dropped" do
    report = curation.call(plan)
    expect([report.ok, report.outcomes.map { [it.status, it.slug, it.reason] }, OpenLanes::Memory.inbox(root:).find("flaky-redis-specs").plans])
      .to eq([true, [[:added, "flaky-redis-specs", nil], [:dropped, nil, "lesson is not an object"]], ["002.00"]])
  end

  context "when the curator does not finish" do
    let(:result) { instance_double(OpenLanes::Execution::Executor::Result, ok: false, note: "Interrupted") }

    it "files nothing and passes on why" do
      report = curation.call(plan)
      expect([report.ok, report.note, report.outcomes, OpenLanes::Memory.inbox(root:).candidates]).to eq([false, "Interrupted", [], []])
    end
  end

  describe "the curator's definition" do
    it "is started by no plan state and holds no tool that writes" do
      expect([agent.handles, agent.allowed_tools & %w[Write Edit Bash], agent.phase.to_s]).to eq([[], [], "memory"])
    end

    it "shows an example line the harness reads back as a proposal" do
      example = agent.prompt[/^ {4}(\{"lesson".*)$/, 1]
      expect(OpenLanes::Memory::Proposal.read(example)).to have_attributes(slug: "real-plan-trees-in-specs", kind: "practice", severity: "high")
    end

    it "passes the secret scan itself, so its own example could be filed" do
      expect(OpenLanes::Memory::Secrets.scan(agent.prompt)).to eq([])
    end
  end
end

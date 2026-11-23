# frozen_string_literal: true

# Decision C11: the terminal's plan table shows what each plan has spent,
# with its cap, read through the same Budget the web board reads.
RSpec.describe OpenLanes::Presentation::Reporter::Spend, :tree do
  def finished(ordinal, cost, id)
    OpenLanes::Events::Event.new(event_id: id,
      kind: "agent_finished",
      at: Time.now,
      plan: ordinal,
      payload: { "round" => 1, "cost_usd" => cost })
  end

  let(:events) { [finished("001.00", 3.2, "a"), finished("002.00", 30.0, "b"), finished("004.00", nil, "c")] }
  let(:cap) { 25.0 }
  let(:budget) { OpenLanes::Engine::Budget.new(cap: -> { cap }, events: -> { events }) }
  let(:spend) { described_class.new(budget) }

  it "shows the spend against the cap" do
    expect(spend.text("001.00")).to eq("$3.20 / $25.00")
  end

  it "is blank for a plan nothing was spent on" do
    expect(spend.text("003.00")).to eq("")
  end

  it "shows a plan whose only runs were unpriced, at $0.00" do
    expect(spend.text("004.00")).to eq("$0.00 / $25.00")
  end

  it "paints a plan at its cap red, and one under it green" do
    expect(%w[002.00 001.00].map { spend.colour(it) }).to eq(%i[red green])
  end

  context "with no cap" do
    let(:cap) { nil }

    it "shows the spend alone" do
      expect(spend.text("001.00")).to eq("$3.20")
    end
  end

  it "shows nothing when the cap cannot be read" do
    broken = OpenLanes::Engine::Budget.new(cap: -> { raise OpenLanes::Error, "bad config" }, events: -> { events })
    expect([described_class.new(broken).text("001.00"), described_class.new(broken).colour("001.00")]).to eq(["", :green])
  end

  describe "in the table" do
    before do
      plans do |t|
        t.plan "001.00", :new, "initial-spec", files: { "spec.md" => spec_body(title: "Initial Spec") }
        t.plan "003.00", :blocked, "pricing", files: { "blocked.md" => "B1. Which tier?" }
      end
    end

    let(:table) { OpenLanes::Presentation::Reporter.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), budget:).render }

    it "heads a Spend column and fills it per plan" do
      lines = table.lines
      aggregate_failures do
        expect(lines.first).to include("Spend")
        expect(lines.grep(/001\.00/).first).to include("$3.20 / $25.00")
        expect(lines.grep(/003\.00/).first).not_to include("$")
      end
    end

    it "keeps the pull requests in one column whatever a plan spent" do
      starts = table.lines.grep(/\[none yet\]/).map { it.index("[none yet]") }
      expect(starts.uniq.size).to eq(1)
    end
  end
end

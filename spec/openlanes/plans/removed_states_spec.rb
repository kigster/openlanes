# frozen_string_literal: true

# X1, X4, X8: three ways out of the active list, each justified by a reason file.
RSpec.describe "plans taken out of the active list", :tree do
  let(:machine) { OpenLanes::Plans::StateMachine }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }

  def plan_with(files, key: :new)
    plans { |t| t.plan "001.00", key, "stale", files: { "spec.md" => spec_body }.merge(files) }
    tree.find("001.00")
  end

  it "makes trashed the only terminal state" do
    expect(OpenLanes::Plans::STATUSES.select(&:terminal?).map(&:key)).to eq([:trashed])
  end

  it "lets anything else be trashed" do
    others = OpenLanes::Plans::STATUSES.map(&:key) - [:trashed]
    expect(machine.inbound.fetch(:trashed)).to match_array(others)
  end

  it "does not discard what is already trashed" do
    expect(machine.inbound.fetch(:discarded)).not_to include(:trashed, :discarded)
    expect(machine.inbound.fetch(:discarded)).to include(:abandoned, :bomb)
  end

  it "does not abandon what was already decided against" do
    expect(machine.inbound.fetch(:abandoned)).not_to include(:abandoned, :discarded, :trashed)
    expect(machine.inbound.fetch(:abandoned)).to include(:blocked, :completed)
  end

  it "does not count a whitespace-only reason" do
    subject = plan_with({ "trashed-reason.md" => "  \n" })
    expect(OpenLanes::Plans.status(:trashed).satisfied_by?(subject)).to be(false)
  end

  it "lets a reason outrank an unanswered block" do
    subject = plan_with({ "trashed-reason.md" => "done", "blocked.md" => "## B1\nwhat?" }, key: :blocked)
    expect(subject.best_fit.key).to eq(:trashed)
  end

  it "ranks trash above discard above abandon" do
    subject = plan_with({ "abandoned-reason.md" => "a", "discarded-reason.md" => "b", "trashed-reason.md" => "c" })
    expect(subject.best_fit.key).to eq(:trashed)
  end

  it "ranks discard above abandon" do
    subject = plan_with({ "abandoned-reason.md" => "a", "discarded-reason.md" => "b" })
    expect(subject.best_fit.key).to eq(:discarded)
  end

  it "still accepts the older discarded.md" do
    subject = plan_with({ "discarded.md" => "no" })
    expect(subject.best_fit.key).to eq(:discarded)
  end

  it "files each state in its own directory" do
    expect(OpenLanes::Plans::REMOVED.to_h { [it, OpenLanes::Plans::Tree.subfolder_for(OpenLanes::Plans.status(it))] })
      .to eq(abandoned: "abandoned", discarded: "discarded", trashed: "trashed")
  end

  it "names each reason file after its state" do
    expect(OpenLanes::Plans::REMOVED.map { OpenLanes::Plans.reason_file(it) })
      .to eq(%w[abandoned-reason.md discarded-reason.md trashed-reason.md])
  end

  context "when a dependency has been removed" do
    before do
      plans do |t|
        t.plan "001.00", :trashed, "gone", under: "trashed", files: { "trashed-reason.md" => "done" }
        t.plan "002.00", :planned, "waiter", files: { "spec.md" => "---\ndepends_on: [\"001.00\"]\n---\n#{spec_body}" }
      end
    end

    it "does not hold the dependent" do
      deps = tree.dependencies
      expect(deps.waiting_on("002.00")).to eq([])
      expect(deps.closed("002.00")).to eq(["001.00"])
      expect(deps.reason("002.00")).to be_nil
    end
  end
end

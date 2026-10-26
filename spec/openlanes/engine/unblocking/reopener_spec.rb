# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Unblocking::Reopener, :tree do
  subject(:reopener) { described_class.new }

  let(:answered) { "## B1 Rebase\n\nShould I?\n\n## A1\n\nyes\n\nAnswered by dana on 2026-10-13\n" }
  let(:plan) { OpenLanes::Plans::Tree.new(dir: plans_root).find("002.00") }
  let(:question) { OpenLanes::Lifecycle::Unblocker::Question.new(number: 1, heading: "Rebase", answered: true) }
  let(:outcome) { instance_double(OpenLanes::Lifecycle::Unblocker::Outcome, subject: plan, waiting: [question]) }
  let(:drain) { OpenLanes::Engine::Unblocking::Drain.new(ordinal: "002.00", agent: "unblocker", rounds: 0) }
  let(:file) { File.read(File.join(plan.feature.path, "blocked.md")) }

  before do
    plans { |t| t.plan "002.00", :blocked, "rebase", files: { "blocked.md" => answered } }
    allow(OpenLanes::UI).to receive(:log)
  end

  it "takes the answer out and says what was refused, and why" do
    OpenLanes::Plans::PlanState.for(plan.feature.path)
                               .journal!(agent: "unblocker", entries: [OpenLanes::Plans::Journal::Entry.new(kind: "note", text: "not a/b/c")])
    reopener.call(drain, outcome)

    aggregate_failures do
      expect(file).not_to match(/^## A1/)
      expect(file).to include("> **Answer not accepted:** yes", "unblocker: not a/b/c")
      expect(OpenLanes::UI).to have_received(:log).with("answer to B1 not accepted: unblocker: not a/b/c", level: :warn, plan: "002.00")
    end
  end

  it "says the broker said nothing when its journal is silent" do
    reopener.call(drain, outcome)

    expect(file).to include("unblocker left it unfolded and said nothing")
  end

  it "reports a blocked.md it cannot read rather than raising" do
    File.delete(File.join(plan.feature.path, "blocked.md"))
    reopener.call(drain, outcome)

    expect(OpenLanes::UI).to have_received(:log).with(/could not reopen the unaccepted answers/, level: :warn, plan: "002.00")
  end
end

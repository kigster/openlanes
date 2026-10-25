# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Steps::Watch, :tree do
  subject(:step) { described_class.new(context, watch:, finishes:, state:) }

  let(:watch) { instance_double(OpenLanes::Engine::PrWatch, due?: true, poll: outcomes) }
  let(:finishes) { instance_double(OpenLanes::Engine::Finishes, keep: nil) }
  let(:state) { instance_double(OpenLanes::Engine::StateFile, :waiting_on= => nil) }
  let(:effects) { instance_double(OpenLanes::Engine::PrOutcomes, apply: applied) }
  let(:applied) { OpenLanes::Engine::PrOutcomes::Applied.new(plan: "033.00", pr: 1, to: :approved, note: "merged") }
  let(:waiting) { OpenLanes::Engine::PrWatch::Outcome.new(plan: "034.00", pr: 2, kind: :waiting) }
  let(:merged) { OpenLanes::Engine::PrWatch::Outcome.new(plan: "033.00", pr: 1, kind: :merged) }
  let(:outcomes) { [waiting, merged] }
  let(:agents) { instance_double(OpenLanes::Agents::Registry, dir: "agents") }
  let(:runner) { instance_double(OpenLanes::Engine::Runner, in_scope: [], tree: OpenLanes::Plans::Tree.new(dir: plans_root), agents:, events: nil) }
  let(:busy) { [] }
  let(:woken) { [] }
  let(:reopened) { [] }
  let(:context) do
    OpenLanes::Engine::Steps::Context.new(runner:, busy: -> { busy }, wake: -> { woken << true }, reopen: ->(o) { reopened << o })
  end

  def settle
    step.call
    step.join
    step.call
  end

  before do
    plans { |t| t.plan "033.00", :completed, "merge-risk" }
    allow(OpenLanes::Engine::PrOutcomes).to receive(:new).and_return(effects)
    allow(OpenLanes::Agents::Registry).to receive(:new).and_return(agents)
    allow(OpenLanes::UI).to receive(:log)
  end

  it "applies what the poll found on the next tick, and wakes the loop" do
    settle

    aggregate_failures do
      expect(effects).to have_received(:apply).with(merged).once
      expect(finishes).to have_received(:keep).with("033.00")
      expect(OpenLanes::UI).to have_received(:log).with("033.00: merged → #{OpenLanes::Plans::STATUS_BY_KEY.fetch(:approved)}")
      expect([reopened, woken]).to eq([["033.00"], [true]])
    end
  end

  it "remembers the pull requests still waiting, for the board and the state file" do
    settle

    aggregate_failures do
      expect(step.waiting_on).to eq("034.00" => [2])
      expect(state).to have_received(:waiting_on=).with("034.00" => [2])
    end
  end

  it "leaves alone a plan something else took meanwhile" do
    busy << "033.00"
    settle

    expect(effects).not_to have_received(:apply)
  end

  it "carries on when the poll dies, and applies nothing" do
    allow(watch).to receive(:poll).and_raise(JSON::ParserError, "unexpected token")
    settle

    aggregate_failures do
      expect(OpenLanes::UI).to have_received(:log).with("pull requests unwatched this time: unexpected token", level: :warn)
      expect(effects).not_to have_received(:apply)
    end
  end

  it "does not poll before the watch is due" do
    allow(watch).to receive(:due?).and_return(false)
    step.call

    expect(step.join).to be_nil
  end
end

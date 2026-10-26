# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Unblocking::Settler do
  subject(:settler) { described_class.new(context, history: ->(o) { forgotten << o }, reopener:) }

  let(:reopener) { instance_double(OpenLanes::Engine::Unblocking::Reopener, call: nil) }
  let(:forgotten) { [] }
  let(:reopened) { [] }
  let(:woken) { [] }
  let(:context) do
    OpenLanes::Engine::Steps::Context.new(runner: nil, busy: -> { [] }, wake: -> { woken << true }, reopen: ->(o) { reopened << o })
  end
  let(:outcome) { instance_double(OpenLanes::Lifecycle::Unblocker::Outcome, ok: true, note: "folded", waiting: [], cleared?: true, folded: [1]) }
  let(:drain) { OpenLanes::Engine::Unblocking::Drain.new(ordinal: "002.00", outcome:, agent: "unblocker", rounds: 0) }

  before { allow(OpenLanes::UI).to receive(:log) }

  it "gives a drained plan's agents their rounds back, and wakes the loop" do
    settler.call(drain)

    aggregate_failures do
      expect([forgotten, reopened, woken]).to eq([["002.00"], ["002.00"], [true]])
      expect(OpenLanes::UI).to have_received(:log).with("unblocked: blocked.md retired", plan: "002.00")
      expect(reopener).not_to have_received(:call)
    end
  end

  it "says how many it folded when blocked.md stays, and reopens what the broker would not take" do
    question = OpenLanes::Lifecycle::Unblocker::Question.new(number: 2, heading: "Why", answered: true)
    allow(outcome).to receive_messages(cleared?: false, waiting: [question])
    settler.call(drain)

    aggregate_failures do
      expect(reopener).to have_received(:call).with(drain, outcome)
      expect(OpenLanes::UI).to have_received(:log).with("unblock folded 1", plan: "002.00")
    end
  end

  it "remembers why a drain failed, until the next answer set is tried" do
    allow(outcome).to receive(:ok).and_return(false)
    settler.call(drain)
    failed = settler.failures.dup
    settler.forget("002.00")

    aggregate_failures do
      expect([failed, settler.failures]).to eq([{ "002.00" => "folded" }, {}])
      expect(OpenLanes::UI).to have_received(:log).with("unblock failed: folded", level: :warn, plan: "002.00")
    end
  end

  it "takes a raised error's message as the reason" do
    settler.call(drain.dup.tap { it.outcome = OpenLanes::Error.new("broker died") })

    expect(settler.failures).to eq("002.00" => "broker died")
  end
end

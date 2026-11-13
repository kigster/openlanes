# frozen_string_literal: true

require_relative "../../live/live_context"

# A desk over a real `.plans` tree, with one 🟡 plan on it, as the
# dispatcher would hand it to a step.
RSpec.shared_context "with a dispatcher desk" do
  include_context "with a live run"

  let(:stay) { false }
  let(:rounds) { nil }
  let(:desk) do
    OpenLanes::Engine::Dispatcher::Desk
      .new(runner:, state: nil, rounds:, clock: OpenLanes::Clock::System, stay:, journal: nil, extensions: nil)
      .tap { it.unblocking = [] }
  end
  let(:plan) { tree.reload.subjects.find { it.feature.ordinal.to_s == "001.00" } }
  let(:coder) { agents.find("backend-coder") }

  before { building("001.00", "tax-rule-dsl") }

  # A job as {OpenLanes::Engine::Dispatcher::Start} would have made it.
  def job_for(subject, agent, round: 1, **fields)
    task = OpenLanes::Engine::Runner::Task.new(agent:, subject:, root: plans_root, checkout: plans_root, round:)
    OpenLanes::Engine::Dispatcher::Job.new(key: "#{subject.feature.ordinal}/#{agent.name}",
      task:,
      state: subject.status.key,
      from: subject.status.key,
      **fields)
  end
end

# frozen_string_literal: true

require_relative "../live/live_context"

# The copilot's lane controls (plan 020.00): stop a plan, restart a lane that
# lost its agent, and change how many agents run at once.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  # Worktree isolation for the concurrency, a dry run so no checkout is made.
  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :worktree,
      jobs: 3,
      dry_run: true,
      plans: scope,
      claims:,
      sleeper: ->(_) {})
  end

  def finish(count)
    executor.release_all(count)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    sleep(0.01) until dispatcher.running.count(&:finished?) >= count ||
                      Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  after { OpenLanes::Execution::Control.reset! }

  describe "#stop_plan" do
    before do
      building("001.00", "tax-rule-dsl")
      start_agents
    end

    it "tells both agents of a pair to stop" do
      expect(dispatcher.stop_plan("001.00")).to contain_exactly("001.00/backend-coder", "001.00/frontend-coder")
    end

    it "writes STOP into each control file" do
      dispatcher.stop_plan("001.00")
      words = dispatcher.running.map { File.read(it.handle.control).strip }
      expect(words).to all(eq(OpenLanes::Execution::Control::STOP))
    end

    it "takes the plan off the run, so nothing starts it again" do
      dispatcher.stop_plan("001.00")
      expect(runner.in_scope).to be_empty
    end

    it "refuses a plan that is neither running nor in scope" do
      expect { dispatcher.stop_plan("009.00") }.to raise_error(OpenLanes::Error, /not on this run's board/)
    end
  end

  describe "#restart_plan" do
    before { building("001.00", "tax-rule-dsl") }

    it "refuses while an agent is working the plan" do
      start_agents
      expect { dispatcher.restart_plan("001.00") }.to raise_error(OpenLanes::Error, /already has an agent/)
    end

    it "refuses a plan that is not on the board" do
      expect { dispatcher.restart_plan("009.00") }.to raise_error(OpenLanes::Error, /not on this node's board/)
    end

    it "dispatches an idle in-scope plan on the next tick" do
      runner.drop_plan("001.00")
      dispatcher.restart_plan("001.00")
      start_agents
      expect(dispatcher.running.map(&:key)).to include("001.00/backend-coder")
    end

    it "forgets the rounds the plan used up, so an exhausted lane runs again" do
      start_agents
      dispatcher.stop_plan("001.00")
      finish(2)
      dispatcher.tick
      dispatcher.restart_plan("001.00")
      start_agents
      expect(dispatcher.running.map(&:key)).to contain_exactly("001.00/backend-coder", "001.00/frontend-coder")
    end
  end

  describe "#concurrency=" do
    before do
      %w[001.00 002.00 003.00].each_with_index { |ordinal, i| building(ordinal, "plan-#{i}") }
      allow(OpenLanes::Agents::Routing).to(receive(:filter).and_wrap_original { |m, list, subject| m.call(list, subject).first(1) })
      start_agents
    end

    it "keeps every running agent when lowered" do
      dispatcher.concurrency = 1
      expect(dispatcher.running.size).to eq(3)
    end

    it "starts nothing until the run is under the new limit" do
      dispatcher.concurrency = 1
      finish(2)
      dispatcher.tick
      expect([runner.jobs, dispatcher.running.size]).to eq([1, 1])
    end

    it "shows the new limit on the board" do
      # A dry run makes no checkout, so there is no worktree root to show.
      allow(runner).to receive(:root).and_return("/checkout")
      dispatcher.concurrency = 2
      expect(dispatcher.board.jobs).to eq(2)
    end

    it "refuses a limit under 1" do
      expect { dispatcher.concurrency = 0 }.to raise_error(OpenLanes::Error, /at least 1/)
    end
  end
end

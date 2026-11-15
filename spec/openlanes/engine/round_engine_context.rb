# frozen_string_literal: true

# A real Runner over a real `.plans` tree, with an executor that only notes
# the round each agent was told and answers with a canned result. Each call
# to `engine` is a new engine as far as the dispatcher can tell, so two calls
# are a restart. The including spec defines `agent_front`, the frontmatter of
# its one agent, and makes its own plan.
RSpec.shared_context "with a restartable engine" do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:agents_dir) { Dir.mktmpdir }
  let(:agent_name) { "researcher" }
  let(:agents) do
    File.write(File.join(agents_dir, "#{agent_name}.md"), "---\nname: #{agent_name}\n#{agent_front}\n---\nbody")
    OpenLanes::Agents::Registry.new(dir: agents_dir)
  end
  let(:folder) { tree.reload.find(OpenLanes::Plans::Ordinal.parse("001.00")).feature.path }
  let(:plan_state) { OpenLanes::Plans::PlanState.for(folder) }
  let(:stages) { plan_state.stages }
  let(:told) { [] }
  let(:note) { "exited 1" }
  let(:spent) { 1 }
  let(:clock) { OpenLanes::Clock::Fake.new(now: Time.now) }
  let(:extensions) { OpenLanes::Engine::Extensions.new(stay: false, auto: false, now: -> { clock.now }) }
  let(:executor) do
    lambda { |_agent, _subject, round: 1, **|
      told << round
      OpenLanes::Execution::Executor::Result.new(ok: false, note:, up: 0, down: spent, subagents: 0, delegated: 0, seconds: 0.0)
    }
  end

  before { OpenLanes::Container.stub("clock", clock) }

  after { FileUtils.rm_rf(agents_dir) }

  def engine(rounds: nil, executor: self.executor, **, &)
    OpenLanes::Engine::Runner.new(tree:, executor:, agents:, isolation: :shared, jobs: 1, rounds:, sleeper: ->(_) {}, extensions:, **).call(&)
  end

  # @return [String] what a run that has gone idle says it is waiting for
  def idle_line
    said = nil
    engine { |d| said = -> { d.send(:idle_reason, tree.reload.subjects) } }
    said.call
  end
end

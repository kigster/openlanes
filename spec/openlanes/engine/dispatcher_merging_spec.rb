# frozen_string_literal: true

# P1 to P5 inside the loop: palpatine runs at 🏁, and what it signed goes
# to {OpenLanes::Engine::Merging}. Merging itself (labels, merges, rebases)
# is its own spec's; here it is a double, and what is asserted is what the
# loop hands it and that palpatine is not started twice.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:stamp) { "2026-10-20 09:00:00 AM PDT" }
  let(:calls) { [] }
  let(:notes) { [] }
  let(:files) { { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n" } }
  let(:merging) { instance_double(OpenLanes::Engine::Merging) }

  def result(succeeded: true, killed: nil)
    OpenLanes::Execution::Executor::Result.new(ok: succeeded, killed:, note: "completed", up: 1, down: 1, subagents: 0, delegated: 0, seconds: 1.0)
  end

  def executor(note, signs: true, **outcome)
    lambda { |agent, subject, round: 1, **|
      calls << [agent.name, subject.status.key]
      if signs
        file = File.join(subject.feature.path, agent.ledger.first)
        OpenLanes::Plans::Ledger.append(file, "> [#{stamp}] [ agent: #{agent.name}   status: Completed, round #{round} (#{note}) ]")
      end
      result(**outcome)
    }
  end

  def run(executor)
    runner = OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:    OpenLanes::Agents::Registry.new.only("palpatine-risk-assessor"),
      isolation: :shared,
      merging:,
      sleeper:   ->(_) {})
    described_class.new(runner:, sleeper: ->(_) {}).run
  end

  def plan = tree.reload.find(OpenLanes::Plans::Ordinal.parse("033.00"))

  before do
    plans { |t| t.plan "033.00", :completed, "merge-risk", files:, prs: [t.open(7, "Part")] }
    assessed = false
    allow(merging).to receive(:assessed?) { assessed }
    allow(merging).to receive_messages(advance: OpenLanes::Engine::Merging::Result.new(note: "waiting"), rebase_queued: [])
    allow(merging).to receive(:assess) do |_, note|
      notes << note
      assessed = true
      OpenLanes::Engine::Merging::Result.new(note: "PR #7 merge-manually: palpatine said manual")
    end
  end

  it "hands palpatine's note to merging, once, and leaves the folder where merging left it" do
    attempts = run(executor("auto #7"))

    aggregate_failures do
      expect(calls).to eq([["palpatine-risk-assessor", :completed]])
      expect(notes).to eq(["auto #7"])
      expect(attempts.last).to have_attributes(to: :completed)
      expect(attempts.last.note).to include("PR #7 merge-manually")
      expect(plan.status.key).to eq(:completed)
    end
  end

  it "reads a palpatine killed before it signed as manual, never as a second try at auto (P4)" do
    run(executor(nil, signs: false, succeeded: false, killed: :timeout))

    aggregate_failures do
      expect(calls.size).to eq(1)
      expect(notes).to eq([nil])
    end
  end
end

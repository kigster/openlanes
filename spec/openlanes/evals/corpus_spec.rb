# frozen_string_literal: true

# The shipped cases are the scorers' own test suite: every `pass/` recording
# must pass and every `fail/` recording must fail. A scorer that stops
# catching a planted failure, or starts failing a good run, shows up here
# before it misjudges a live agent.
RSpec.describe "the shipped eval corpus" do
  let(:cases) { OpenLanes::Evals.cases }

  it "covers every agent" do
    expect(cases.map(&:agent).uniq).to match_array(OpenLanes::Agents.registry.all.map(&:name))
  end

  it "holds leah, palpatine and r2d2 to two different depths each" do
    depths = cases.group_by(&:agent).transform_values { |list| list.map(&:depth).uniq.size }

    expect(depths.slice("leah-researcher", "palpatine-planner", "r2d2-mechanic").values).to all(be >= 2)
  end

  OpenLanes::Evals.cases.map(&:to_s).each do |name|
    describe name do
      let(:kase) { cases.find { it.to_s == name } }

      it "ships both recordings" do
        expect([kase.recording(:pass), kase.recording(:fail)]).to all(be_a(OpenLanes::Evals::Recording))
      end

      it "passes its pass/ recording" do
        expect(OpenLanes::Evals.score_recording(kase, :pass).failures.map { "#{it.name}: #{it.detail}" }).to eq([])
      end

      it "fails its fail/ recording" do
        expect(OpenLanes::Evals.score_recording(kase, :fail).passed?).to be(false)
      end

      it "bounds its own depth" do
        expect(kase.bounds).not_to be_empty
      end
    end
  end
end

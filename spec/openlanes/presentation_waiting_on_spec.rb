# frozen_string_literal: true

RSpec.describe OpenLanes::Presentation, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:pid) { Process.pid }
  let(:state) { OpenLanes::Engine::StateFile.new(path: OpenLanes::Engine::StateFile.for(tree), pid:) }

  before do
    plans { |t| t.plan "002.00", :in_review, "waiting", files: { "spec.md" => spec_body }, prs: [t.open(12, "b")] }
    state.begin_run!(root: File.dirname(plans_root))
    state.waiting_on = { "002.00" => [12] }
    state.save
  end

  context "when the engine that watched is up" do
    it "says who owes what in the status table" do
      expect(described_class.reporter(tree:).render).to include("waiting on you: PR #12")
    end
  end

  context "when that engine is gone" do
    # A pid no process holds: the run that wrote the file has exited.
    let(:pid) { (2**22) + 12_345 }

    it "says nothing, since nobody is watching any more" do
      expect(described_class.reporter(tree:).render).not_to include("waiting on you")
    end
  end

  # A run that does not watch (no stay, or merge.by: auto) never rewrites the
  # map, so what the previous run's watch saw must not survive its start.
  it "says nothing once a new run begins, until its own watch reports" do
    later = OpenLanes::Engine::StateFile.new(path: state.path, pid:).load
    later.begin_run!(root: File.dirname(plans_root))
    later.save

    expect(described_class.waiting_on(tree)).to eq({})
  end

  it "says nothing with no state file at all" do
    File.delete(state.path)

    expect(described_class.waiting_on(tree)).to eq({})
  end
end

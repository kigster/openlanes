# frozen_string_literal: true

# I1: X7's rows stay true only if the poller asks about removed plans at all.
RSpec.describe OpenLanes::Engine::Runner, :tree do
  it "lists removed plans for the watch, and not the rest" do
    plans do |t|
      t.plan "001.00", :new, "open", files: { "spec.md" => "x\n" }
      t.plan "002.00", :trashed, "gone", under: "trashed", files: { "trashed-reason.md" => "why" }
      t.plan "003.00", :approved, "done", under: "archive", files: {}
    end
    runner = described_class.allocate
    tree = OpenLanes::Plans::Tree.new(dir: plans_root)
    runner.instance_variable_set(:@dropped, [])
    runner.instance_variable_set(:@plans, nil)
    allow(runner).to receive(:tree).and_return(tree)
    expect(runner.removed_in_scope.map { it.feature.ordinal.to_s }).to eq(["002.00"])
  end
end

# frozen_string_literal: true

# X7: GitHub's news keeps a removed plan's rows true and moves nothing.
RSpec.describe OpenLanes::Engine::PrOutcomes, :tree do
  let(:effects) { described_class.new(tree_dir: plans_root, agents: OpenLanes::Agents::Registry.new) }
  let(:everything) { OpenLanes::Plans::Tree.new(dir: plans_root, all: true) }

  def outcome(number, kind) = OpenLanes::Engine::PrWatch::Outcome.new(plan: "004.00", pr: number, kind:, to: nil, comments: [])

  def removed(state, dir)
    plans do |t|
      t.plan "004.00", state, "gone", under: dir, files: { OpenLanes::Plans.reason_file(state) => "why" }, prs: [t.open(14, "a"), t.open(15, "b")]
    end
  end

  { trashed: "trashed", discarded: "discarded", abandoned: "abandoned" }.each do |state, dir|
    %i[merged closed].each do |kind|
      it "records a #{kind} pull request for a plan in #{dir}/ and leaves the folder where it is" do
        removed(state, dir)
        path = everything.find("004.00").feature.path
        effects.apply(outcome(14, kind))
        subject = everything.reload.find("004.00")
        expect(subject.feature.path).to eq(path)
        expect(subject.pull_requests.find { it.number.to_s.delete("#") == "14" }.state).to match(/#{kind == :merged ? "merged" : "closed"}/i)
      end
    end

    it "fires no merge side effects for a plan in #{dir}/" do
      removed(state, dir)
      effects.apply(outcome(14, :merged))
      file = File.join(everything.reload.find("004.00").feature.path, "state.json")
      expect(File.exist?(file) ? File.read(file) : "").not_to include("merged")
    end
  end

  it "does not reject a removed plan back into the active list" do
    removed(:trashed, "trashed")
    path = everything.find("004.00").feature.path
    effects.apply(OpenLanes::Engine::PrWatch::Outcome.new(plan: "004.00", pr: 14, kind: :rejected, to: :rejected, comments: []))
    expect(everything.reload.find("004.00").feature.path).to eq(path)
  end

  it "writes discarded-reason.md and rewires dependents when the last pull request closes" do
    plans do |t|
      t.plan "001.00", :planned, "waiter", files: { "spec.md" => "---\ndepends_on: [\"004.00\"]\n---\n#{spec_body}" }
      t.plan "003.00", :new, "base", files: { "spec.md" => spec_body }
      t.plan "004.00", :ready_for_review, "pr", files: { "spec.md" => "---\ndepends_on: [\"003.00\"]\n---\n#{spec_body}", "plan.md" => "## U\n" }, prs: [t.open(14, "a")]
    end
    effects.apply(outcome(14, :closed))
    expect(everything.reload.find("004.00").read("discarded-reason.md")).to include("#14")
    expect(OpenLanes::Plans::Spec.for(everything.find("001.00")).depends_on).to eq(["003.00"])
  end
end

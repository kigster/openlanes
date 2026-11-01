# frozen_string_literal: true

# X9: an ordering the plans declared survives the removal of the plan in the middle.
RSpec.describe OpenLanes::Lifecycle::Rewiring, :tree do
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }

  def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

  def chain(edges, states: {}, under: {})
    plans do |t|
      edges.each do |ordinal, deps|
        t.plan ordinal,
          states.fetch(ordinal, :planned),
          "p#{ordinal.delete(".")}",
          under: under[ordinal],
          files: { "plan.md" => "## U\n", "spec.md" => deps ? needs(*deps) : spec_body }.merge(reason(states[ordinal]))
      end
    end
  end

  def reason(state) = OpenLanes::Plans::REMOVED.include?(state) ? { OpenLanes::Plans.reason_file(state) => "x" } : {}

  def rewire(*removed) = described_class.new(tree:).then { it.apply(it.plan(removed)) }

  def after(ordinal) = OpenLanes::Plans::Spec.for(tree.reload.everything.find(ordinal)).depends_on

  it "joins A to C when B leaves A -> B -> C" do
    chain({ "001.00" => ["002.00"], "002.00" => ["003.00"], "003.00" => nil })
    rewire("002.00")
    expect(after("001.00")).to eq(["003.00"])
  end

  it "hands on all of B's dependencies, sorted" do
    chain({ "001.00" => ["002.00"], "002.00" => %w[004.00 003.00], "003.00" => nil, "004.00" => nil })
    rewire("002.00")
    expect(after("001.00")).to eq(%w[003.00 004.00])
  end

  it "keeps A's other entries without duplicating one it inherits" do
    chain({ "001.00" => %w[002.00 003.00], "002.00" => ["003.00"], "003.00" => nil })
    rewire("002.00")
    expect(after("001.00")).to eq(["003.00"])
  end

  [%w[002.00 003.00], %w[003.00 002.00]].each do |order|
    it "reaches the same result removing #{order.join(" then ")} together" do
      chain({ "001.00" => ["002.00"], "002.00" => ["003.00"], "003.00" => ["004.00"], "004.00" => nil })
      rewire(*order)
      expect(after("001.00")).to eq(["004.00"])
    end
  end

  it "writes [none] when B has nothing to hand on" do
    chain({ "001.00" => ["002.00"], "002.00" => nil })
    rewire("002.00")
    expect(tree.reload.find("001.00").read("spec.md")).to start_with("---\ndepends_on: [none]\n---\n")
  end

  it "does not inherit a dependency already done" do
    chain({ "001.00" => ["002.00"], "002.00" => ["003.00"], "003.00" => nil }, states: { "003.00" => :approved }, under: { "003.00" => "archive" })
    rewire("002.00")
    expect(after("001.00")).to eq([])
  end

  it "never makes a plan depend on itself" do
    chain({ "001.00" => ["002.00"], "002.00" => ["001.00"] })
    rewire("002.00")
    expect(after("001.00")).to eq([])
  end

  it "terminates when the removed plans wait on each other" do
    chain({ "001.00" => ["002.00"], "002.00" => ["003.00"], "003.00" => ["002.00"] })
    rewire("002.00", "003.00")
    expect(after("001.00")).to eq([])
  end

  it "rewrites a deferred dependent" do
    chain({ "001.00" => ["002.00"], "002.00" => ["003.00"], "003.00" => nil }, states: { "001.00" => :deferred }, under: { "001.00" => "deferred" })
    rewire("002.00")
    expect(after("001.00")).to eq(["003.00"])
  end

  it "leaves an archived dependent as it shipped" do
    chain({ "001.00" => ["002.00"], "002.00" => ["003.00"], "003.00" => nil }, states: { "001.00" => :approved }, under: { "001.00" => "archive" })
    expect(rewire("002.00")).to be_empty
    expect(after("001.00")).to eq(["002.00"])
  end

  it "changes only the depends_on line" do
    plans do |t|
      t.plan "001.00", :planned, "a", files: { "spec.md" => "---\nstarts: planning # why\ndepends_on: [\"002.00\"] # keep\nlane: full\n---\n\n# depends_on: [\"002.00\"]\n" }
      t.plan "002.00", :planned, "b", files: { "spec.md" => needs("003.00") }
      t.plan "003.00", :planned, "c", files: { "spec.md" => spec_body }
    end
    rewire("002.00")
    expect(tree.reload.find("001.00").read("spec.md"))
      .to eq("---\nstarts: planning # why\ndepends_on: [\"003.00\"] # keep\nlane: full\n---\n\n# depends_on: [\"002.00\"]\n")
  end

  it "rewrites a list written in block style" do
    plans do |t|
      t.plan "001.00", :planned, "a", files: { "spec.md" => "---\ndepends_on:\n  - \"002.00\"\nlane: full\n---\nbody\n" }
      t.plan "002.00", :planned, "b", files: { "spec.md" => spec_body }
    end
    rewire("002.00")
    expect(tree.reload.find("001.00").read("spec.md")).to eq("---\ndepends_on: [none]\nlane: full\n---\nbody\n")
  end

  it "reports a dependent it cannot parse and leaves it untouched" do
    broken = "---\ndepends_on: [\"002.00\"\n---\nbody\n"
    plans do |t|
      t.plan "001.00", :planned, "a", files: { "spec.md" => broken }
      t.plan "002.00", :planned, "b", files: { "spec.md" => spec_body }
    end
    edits = rewire("002.00")
    expect(edits.map(&:problem)).to all(match(/001\.00|spec\.md/))
    expect(edits.size).to eq(1)
    expect(tree.reload.find("001.00").read("spec.md")).to eq(broken)
  end

  it "describes each edit and writes nothing when only planned" do
    chain({ "001.00" => ["002.00"], "002.00" => %w[003.00 004.00], "003.00" => nil, "004.00" => nil })
    edits = described_class.new(tree:).plan(["002.00"])
    expect(edits.map(&:to_s)).to eq(["001.00: 002.00 → 003.00, 004.00"])
    expect(after("001.00")).to eq(["002.00"])
  end
end

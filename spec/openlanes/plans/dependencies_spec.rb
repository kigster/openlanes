# frozen_string_literal: true

# Only `depends_on:` is ever written; who a plan blocks is derived, so the
# blocking plan's own spec.md must never change for it (N6).
RSpec.describe OpenLanes::Plans::Dependencies, :tree do
  subject(:deps) { tree.dependencies }

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }

  def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

  def spec_path(ordinal) = File.join(tree.find(ordinal).feature.path, "spec.md")

  context "when 050 depends on an open 034" do
    before do
      plans do |t|
        t.plan "034.00", :planned, "parser", files: { "spec.md" => spec_body }
        t.plan "050.00", :planned, "printer", files: { "spec.md" => needs("034.00") }
        t.plan "060.00", :planned, "unchecked", files: { "spec.md" => spec_body }
      end
    end

    it "derives blocks_of without writing to the blocking plan" do
      before = File.binread(spec_path("034.00"))

      expect(tree.blocks_of("034.00")).to eq(["050.00"])
      expect(File.binread(spec_path("034.00"))).to eq(before)
    end

    it "keeps 050 waiting on 034 and gives the reason" do
      expect(deps.waiting_on("050.00")).to eq(["034.00"])
      expect(deps.reason("050.00")).to eq("waiting on 034.00")
      expect(deps.reason("034.00")).to be_nil
    end

    it "tells an absent key from a declared one" do
      expect(deps.depends_on("060.00")).to be_nil
      expect(deps.depends_on("050.00")).to eq(["034.00"])
      expect(deps.blocks_of("060.00")).to eq([])
    end

    it "is dropped by Tree#reload" do
      first = tree.dependencies
      expect(tree.reload.dependencies).not_to equal(first)
    end
  end

  context "with a done, a blocked and an unknown dependency" do
    before do
      plans do |t|
        t.plan "010.00", :approved, "shipped", files: { "spec.md" => spec_body }, prs: [t.merged(1, "Ship")]
        t.plan "020.00", :product_blocked, "stuck", files: { "blocked.md" => "## B1 Which?\n" }
        t.plan "030.00", :planned, "waits", files: { "spec.md" => needs("010.00", "020.00", "099.00") }
      end
    end

    it "ignores the done one and waits on the blocked and unknown ones" do
      expect(deps.waiting_on("030.00")).to eq(%w[020.00 099.00])
      expect(deps.closed("030.00")).to eq(["010.00"])
      expect(deps.unknown("030.00")).to eq(["099.00"])
    end
  end

  context "with a two-plan cycle" do
    before do
      plans do |t|
        t.plan "034.00", :planned, "a", files: { "spec.md" => needs("050.00") }
        t.plan "050.00", :planned, "b", files: { "spec.md" => needs("034.00") }
      end
    end

    it "reports the cycle from each side, starting at the asked plan" do
      expect(deps.cycles).to eq([%w[034.00 050.00 034.00]])
      expect(deps.cycle_of("050.00")).to eq(%w[050.00 034.00 050.00])
      expect(deps.reason("034.00")).to eq("cycle: 034.00 → 050.00 → 034.00")
    end
  end

  context "with a three-plan cycle and a plan hanging off it" do
    before do
      plans do |t|
        t.plan "001.00", :planned, "a", files: { "spec.md" => needs("002.00") }
        t.plan "002.00", :planned, "b", files: { "spec.md" => needs("003.00") }
        t.plan "003.00", :planned, "c", files: { "spec.md" => needs("001.00") }
        t.plan "004.00", :planned, "d", files: { "spec.md" => needs("001.00") }
      end
    end

    it "finds the ring once and leaves the plan off it out" do
      expect(deps.cycles).to eq([%w[001.00 002.00 003.00 001.00]])
      expect(deps.cycle_of("002.00")).to eq(%w[002.00 003.00 001.00 002.00])
      expect(deps.cycle_of("004.00")).to be_nil
      expect(deps.reason("004.00")).to eq("waiting on 001.00")
    end
  end
end

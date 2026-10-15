# frozen_string_literal: true

# Finished, deferred and discarded plans live one level down (decision N3),
# so the top level is what somebody may still work on. Their numbers are
# still taken, which is the half that bites if a reader forgets them.
RSpec.describe OpenLanes::Plans::Tree, :tree do
  before do
    plans do |t|
      t.plan "001.00", :building, "open-one", files: { "plan.md" => "## Units\n" }
      t.plan "002.00", :approved, "shipped", under: "archive", archived_on: Date.new(2026, 9, 1)
      t.plan "003.00", :deferred, "later", under: "deferred", archived_on: Date.new(2026, 9, 2)
      t.plan "004.00", :discarded, "dropped", under: "abandoned", archived_on: Date.new(2026, 9, 3)
      t.plan "000.00", :new, "first", files: { "spec.md" => spec_body }
    end
  end

  let(:tree) { described_class.new(dir: plans_root) }

  it "reads only the top level by default, and never calls a subfolder a plan or a stray" do
    aggregate_failures do
      expect(tree.ordinals.map(&:to_s)).to eq(%w[000.00 001.00])
      expect(tree.skipped).to be_empty
      expect(tree.find("002.00")).to be_nil
    end
  end

  it "reads every subfolder with all: true, open plans first, then archive, deferred, abandoned" do
    everything = described_class.new(dir: plans_root, all: true)

    aggregate_failures do
      expect(everything.ordinals.map(&:to_s)).to eq(%w[000.00 001.00 002.00 003.00 004.00])
      expect(everything.find("002.00").feature.archived_on).to eq(Date.new(2026, 9, 1))
      expect(everything.find("004.00").status.key).to eq(:discarded)
    end
  end

  it "orders by group before number, so an archived plan never sorts among open ones" do
    plans { |t| t.plan "005.00", :new, "late", files: { "spec.md" => spec_body } }
    plans { |t| t.plan "000.01", :deployed, "early", under: "archive", archived_on: Date.new(2026, 1, 1) }

    expect(tree.everything.reload.ordinals.map(&:to_s)).to eq(%w[000.00 001.00 005.00 000.01 002.00 003.00 004.00])
  end

  it "counts every number as taken, the subfolders included" do
    expect(tree.taken.map(&:to_s)).to contain_exactly("000.00", "001.00", "002.00", "003.00", "004.00")
  end

  it "reports a number claimed both at the top and in a subfolder as a duplicate" do
    plans { |t| t.plan "002.00", :new, "reused", files: { "spec.md" => spec_body } }

    expect(tree.duplicates.keys.map(&:to_s)).to eq(%w[002.00])
  end

  it "names the subfolder each inactive state belongs in" do
    aggregate_failures do
      expect(described_class.subfolder_for(OpenLanes::Plans.status(:approved))).to eq("archive")
      expect(described_class.subfolder_for(OpenLanes::Plans.status(:deployed))).to eq("archive")
      expect(described_class.subfolder_for(OpenLanes::Plans.status(:deferred))).to eq("deferred")
      expect(described_class.subfolder_for(OpenLanes::Plans.status(:discarded))).to eq("abandoned")
      expect(described_class.subfolder_for(OpenLanes::Plans.status(:building))).to be_nil
    end
  end

  describe ".plan_folder" do
    it "looks through an inactive subfolder to the plan inside it" do
      aggregate_failures do
        expect(described_class.plan_folder(".plans/archive/002.00━━✅━━❯[2026-09-01]━━x/spec.md"))
          .to eq("002.00━━✅━━❯[2026-09-01]━━x")
        expect(described_class.plan_folder(".plans/001.00━━🟡━━❯y/plan.md")).to eq("001.00━━🟡━━❯y")
        expect(described_class.plan_folder(".plans/INDEX.md")).to be_nil
        expect(described_class.plan_folder(".plans/archive/README.md")).to be_nil
        expect(described_class.plan_folder("lib/openlanes.rb")).to be_nil
      end
    end
  end
end

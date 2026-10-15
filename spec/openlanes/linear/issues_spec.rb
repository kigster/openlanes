# frozen_string_literal: true

# `linear.md` is the memory that makes a second import idempotent. It has to
# survive the round trip, because the alternative to reading it back is either
# duplicating every issue or searching Linear by title on every run.
RSpec.describe OpenLanes::Linear::Issues, :tree do
  subject(:record) { described_class.new(dir: folder) }

  let(:folder) { File.join(plans_root, "002.00━━✅━━❯dev-foundation") }

  let(:issues) do
    [OpenLanes::Linear::Issue.new(unit: "PR-1",
      identifier: "TAX-41",
      url: "https://linear.app/team/TAX/issue/TAX-41",
      title: "PR-1 — Test rig | rigging",
      state: "Done",
      digest: "9f2c1a04")]
  end

  let(:project) { { name: "US Tax Law: Self Contained Ruby Gem", url: "https://linear.app/p-1" } }

  before do
    plans { |t| t.plan "002.00", :approved, "dev-foundation", prs: [t.merged(2, "Test rig")] }
    record.write(team: "TAX", project:, issues:)
  end

  describe "the round trip" do
    it "reads back every issue it wrote" do
      expect(described_class.new(dir: folder).all.map(&:identifier)).to eq(["TAX-41"])
    end

    it "keeps the url, so a reader can click through to Linear" do
      expect(described_class.new(dir: folder).all.first.url).to end_with("TAX-41")
    end

    it "keeps the fingerprint, which is the whole reason the file exists" do
      expect(described_class.new(dir: folder).all.first.digest).to eq("9f2c1a04")
    end

    it "reads back the project it was filed under" do
      expect(described_class.new(dir: folder).project).to eq(project)
    end

    # A `|` ends a cell, and "PR-1 — Test rig | rigging" is not an unusual
    # title. The escaping has to survive both directions or the title changes
    # every time it is read.
    it "survives a title containing the character that ends a table cell" do
      expect(described_class.new(dir: folder).all.first.title).to eq("PR-1 — Test rig | rigging")
    end

    it "indexes by work unit, which is how the import looks things up" do
      expect(described_class.new(dir: folder).by_unit.keys).to eq(["PR-1"])
    end
  end

  describe "a plan that has never been imported" do
    it "has no issues rather than failing to read a file that is not there" do
      empty = described_class.new(dir: plans_root)

      aggregate_failures do
        expect(empty.exist?).to be(false)
        expect(empty.all).to be_empty
        expect(empty.project).to be_nil
      end
    end
  end

  describe ".digest" do
    it "answers the same for the same payload" do
      expect(described_class.digest(a: 1)).to eq(described_class.digest(a: 1))
    end

    it "answers differently when anything at all has changed" do
      expect(described_class.digest(a: 1)).not_to eq(described_class.digest(a: 2))
    end
  end

  it "warns the reader off the one column they must not hand-edit" do
    expect(File.read(File.join(folder, "linear.md"))).to include("Do not hand-edit the")
  end
end

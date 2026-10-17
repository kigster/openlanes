# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::ProgressLog do
  describe ".status_cell" do
    it "leaves two spaces between a status's emoji and its label" do
      expect(described_class.status_cell("🔴 Changes Requested")).to eq("🔴  Changes Requested")
    end

    it "passes a value with no label through" do
      expect(described_class.status_cell("Planned")).to eq("Planned")
      expect(described_class.status_cell(nil)).to be_nil
    end
  end

  describe ".default_path" do
    it "names the checkout and a digest of its path, so same-named checkouts do not share a log" do
      one = described_class.default_path("/work/a/minesweeper")
      other = described_class.default_path("/work/b/minesweeper")
      aggregate_failures do
        expect(File.basename(one)).to match(/\Aopenlanes-minesweeper-\h{6}\.log\z/)
        expect(one).not_to eq(other)
        expect(File.dirname(one)).to eq(Dir.tmpdir)
        expect(described_class.default_path("/work/a/minesweeper/")).to eq(one)
      end
    end

    it "names the process that logs" do
      expect(File.basename(described_class.default_path("/work/widgets", kind: "web"))).to match(/\Aopenlanes-web-widgets-\h{6}\.log\z/)
    end
  end
end

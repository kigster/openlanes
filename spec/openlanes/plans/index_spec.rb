# frozen_string_literal: true

# `openlanes index` — the plans as one browsable page. The property that
# matters is that its links work, because the file it replaced was hand-written
# and every one of its 82 links pointed at a folder name that `resync dirs` had
# since padded to NNN.MM underneath it.
RSpec.describe OpenLanes::Plans::Index, :tree do
  subject(:index) { described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), project: "Test App") }

  let(:document) { index.render }

  let!(:tree) do
    plans do |t|
      t.plan "001.00",
        :new,
        "initial-spec",
        files: { "spec.md" => spec_body(title: "Initial Spec", goal: "Answer **one** question, using `numeric`.") }
      t.plan "002.00",
        :approved,
        "dev-foundation",
        files: { "spec.md" => spec_body, "plan.md" => "# Plan" },
        prs:   [t.merged(2, "Frontend test rig"), t.merged(3, "Rails foundation")]
      t.plan "003.00", :blocked, "pricing", files: { "blocked.md" => "B1. Which tier?" }
    end
  end

  describe "#render" do
    it "gives every plan a heading carrying its number and state" do
      expect(document.scan(/^## (\d{3}\.\d{2}) — (\S+)/).map(&:first)).to eq(%w[001.00 002.00 003.00])
    end

    it "names the project" do
      expect(document).to start_with("# Project Test App")
    end

    # The whole reason this is generated rather than written.
    it "percent-encodes the emoji, rules and pointer in a folder name, which a raw href breaks on" do
      expect(document).to include('href="001.00%E2%94%81%E2%94%81%E2%9A%AA%E2%94%81%E2%94%81%E2%9D%AFinitial-spec/spec.md"')
    end

    it "links every pull request a plan records" do
      aggregate_failures do
        expect(document).to include("/pull/2", "/pull/3")
        expect(document).to include("Merged 🟣")
      end
    end

    it "says so plainly when a plan has no pull requests" do
      expect(document[%r{001\.00.*?</table>}m]).to include("<em>—</em>")
    end

    it "orders the documents by lifecycle, not by alphabet" do
      links = document.scan(%r{<a href="002\.00[^"]*">([^<]+)</a>}).flatten

      expect(links).to eq(["Spec", "Plan", "Pull Requests"])
    end

    # GitHub stops parsing markdown inside a raw HTML block, so a goal quoted
    # verbatim would show its own asterisks and backticks to the reader.
    it "translates the markdown a goal is written in, since HTML suppresses it" do
      aggregate_failures do
        expect(document).to include("<strong>one</strong>")
        expect(document).to include("<code>numeric</code>")
        expect(document).not_to include("**one**")
      end
    end

    it "escapes HTML in a status label rather than emitting it raw" do
      expect(document).to include("Approved &amp; Merged")
    end

    # A ⭕ folder holding `blocked.md` is consistent, so the fixture needs a
    # folder that actually lies: ✅ Approved & Merged with a pull request open.
    context "when a folder's name is not justified by its contents" do
      let!(:tree) do
        plans { |t| t.plan "004.00", :approved, "lying", prs: [t.open(5, "still open")] }
      end

      it "says so on the page rather than presenting it as fine" do
        expect(document).to match(/⚠️.*1 pull request still open/)
      end
    end

    it "counts the plans at the foot" do
      expect(document).to include("3 plans")
    end
  end

  describe "#write" do
    it "lands next to the plans it describes" do
      expect(File.basename(index.write)).to eq("INDEX.md")
    end

    it "goes where it is told instead, when it is told" do
      target = File.join(plans_root, "elsewhere.md")

      expect(index.write(target)).to eq(target)
    end
  end

  describe "an empty tree" do
    let!(:tree) { plans }

    it "is still a document rather than a crash" do
      expect(document).to include("# Project Test App", "0 plans")
    end
  end
end

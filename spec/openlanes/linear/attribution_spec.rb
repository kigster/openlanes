# frozen_string_literal: true

# Attribution is the tail end of `resync prs`: pull requests whose titles
# carry no [NNN.MM] and never will. Every answer it gives is a guess, so what
# these examples protect is not just the matching but the refusals — a tie
# refused, a thin overlap refused — and the sentence explaining each one.
RSpec.describe OpenLanes::Linear::Attribution, :tree do
  subject(:attribution) { described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root)) }

  let!(:tree) do
    plans do |t|
      t.plan "101.00", :new, "ledger-carryforward-vintages"
      t.plan "102.00", :new, "invoice-export-pipeline"
      t.plan "103.00", :new, "pipeline-invoice-export"
      t.plan "104.00", :new, "corpus-sync"
    end
  end

  def pull(title, number: "90")
    OpenLanes::Plans::PullRequest.new(number:,
      title:,
      url: "https://github.com/example/repo/pull/#{number}",
      state: "Merged 🟣")
  end

  def place(title, bodies: {})
    attribution.call([pull(title)], bodies:).first
  end

  describe "placing by title" do
    it "claims the folder whose name the title covers" do
      placed = place("Add ledger carryforward vintages support")

      aggregate_failures do
        expect(placed).to be_placed
        expect(placed.subject.feature.slug).to eq("ledger-carryforward-vintages")
        expect(placed.why).to eq("title: covers 100% of the folder name")
      end
    end

    # `vintages` in the title, `vintage` in nothing here — the other way: the
    # inflection gap is the error attribution exists to absorb.
    it "matches a word to its inflection rather than demanding the exact form" do
      placed = place("Carry the ledger vintage carryforwards over")

      expect(placed.subject.feature.slug).to eq("ledger-carryforward-vintages")
    end
  end

  describe "refusing" do
    it "matches no folder at all when the title shares nothing with any name" do
      placed = place("Zebra quagga migration")

      aggregate_failures do
        expect(placed).not_to be_placed
        expect(placed.why).to eq("matched no folder at all")
      end
    end

    # "the", "fix" and "app" are all noise, so nothing is left to match on —
    # the early return, not the zero-overlap path.
    it "treats a title made entirely of noise as saying nothing" do
      placed = place("Fix the app")

      aggregate_failures do
        expect(placed).not_to be_placed
        expect(placed.score).to eq(0.0)
        expect(placed.why).to eq("matched no folder at all")
      end
    end

    it "refuses a coverage below the floor, saying how far short it fell" do
      placed = place("Track vintages across the year")

      aggregate_failures do
        expect(placed).not_to be_placed
        expect(placed.why).to eq("33% of a folder name is not enough")
      end
    end

    # Half of a two-word name is one shared word, which was already
    # established as too thin — the fraction clears the floor and the
    # absolute word count still refuses it.
    it "refuses a match carried by fewer than three words, whatever the fraction" do
      placed = place("Rebuild corpus loading throughout")

      aggregate_failures do
        expect(placed).not_to be_placed
        expect(placed.why).to eq("50% of a folder name is not enough")
      end
    end

    # Two folders matching equally well is evidence neither is right, not a
    # reason to pick the first.
    it "refuses a tie and names the rivals" do
      placed = place("Rework the invoice export pipeline")

      aggregate_failures do
        expect(placed).not_to be_placed
        expect(placed.rivals).to contain_exactly("102.00━━⚪━━❯invoice-export-pipeline", "103.00━━⚪━━❯pipeline-invoice-export")
        expect(placed.why).to eq("2 folders matched equally well (100%)")
      end
    end
  end

  describe "the second pass through the description" do
    it "reads the description when the title said nothing useful" do
      placed = place("Big improvement",
        bodies: { "90" => "Rework the ledger carryforward vintages handling." })

      aggregate_failures do
        expect(placed).to be_placed
        expect(placed.subject.feature.slug).to eq("ledger-carryforward-vintages")
        expect(placed.source).to eq("title and description")
        expect(placed.why).to eq("title and description: covers 100% of the folder name")
      end
    end

    it "gives up when the description is all boilerplate the cleaning removes" do
      placed = place("Big improvement",
        bodies: { "90" => "<!-- template -->\n```ruby\ncode\n```" })

      expect(placed).not_to be_placed
    end

    it "returns the title's own refusal when the description matches nothing either" do
      placed = place("Big improvement",
        bodies: { "90" => "Nothing relevant whatsoever, honestly speaking." })

      aggregate_failures do
        expect(placed).not_to be_placed
        expect(placed.widened).to be(false)
      end
    end

    it "leaves a pull request with no recorded description on the title's verdict" do
      placed = place("Big improvement", bodies: {})

      expect(placed).not_to be_placed
    end
  end

  describe "#opening_words" do
    it "strips comments, fences and list furniture before reading" do
      words = attribution.opening_words(<<~BODY)
        <!-- stacking note -->
        ```ruby
        code_that_should_not_match
        ```
        - Rework the ledger carryforward handling
      BODY

      aggregate_failures do
        expect(words).to include("ledger", "carryforward")
        expect(words).not_to include("stacking", "code_that_should_not_match")
      end
    end

    # Further down, a description turns into checklists and generated tables
    # that read the same on every pull request in the repository.
    it "stops after the opening, before the boilerplate begins" do
      body = ((%w[ledger] * 1) + Array.new(60) { |i| "distinct#{i}word" }).join(" ")

      expect(attribution.opening_words(body).size).to eq(described_class::OPENING_WORDS)
    end

    it "reads nothing from a missing description" do
      expect(attribution.opening_words(nil)).to eq([])
    end
  end

  describe "the Placed record" do
    it "renders its score as a percentage of the folder name" do
      expect(place("Add ledger carryforward vintages support").percent).to eq("100%")
    end

    it "credits the title alone when the first pass sufficed" do
      expect(place("Add ledger carryforward vintages support").source).to eq("title")
    end
  end
end

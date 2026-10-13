# frozen_string_literal: true

# Linear has five workflow state types and every workspace renames them, so a
# placement carries both the type it means and the name it would prefer.
RSpec.describe OpenLanes::Linear do
  describe "PLACEMENTS" do
    # The failure this guards is silent: a sixteenth state gets added to
    # STATUSES, nothing here changes, and its plans import as whatever the
    # fallback happens to be with no indication anything was missed.
    it "accounts for every state the folder names can carry, placed or deliberately not" do
      accounted = described_class::PLACEMENTS.keys + described_class::UNPLACED.keys

      expect(accounted).to match_array(OpenLanes::Plans::STATUSES.map(&:key))
    end

    it "never both places a state and declares it unplaceable" do
      expect(described_class::PLACEMENTS.keys & described_class::UNPLACED.keys).to be_empty
    end

    it "uses only the five types Linear actually has" do
      types = described_class::PLACEMENTS.values.map(&:type).uniq

      expect(types - described_class::TYPES).to be_empty
    end

    it "labels the states whose meaning the type cannot carry" do
      aggregate_failures do
        expect(described_class::PLACEMENTS[:blocked].labels).to eq(%w[blocked])
        expect(described_class::PLACEMENTS[:product_blocked].labels).to eq(%w[blocked-on-product])
        expect(described_class::PLACEMENTS[:deployed].labels).to eq(%w[deployed])
      end
    end

    # ⭕️ and 🅱️ are the same position on a board and different reasons.
    it "distinguishes the two blocks by label, since both sit in the same column" do
      technical = described_class::PLACEMENTS[:blocked]
      product = described_class::PLACEMENTS[:product_blocked]

      aggregate_failures do
        expect(technical.type).to eq(product.type)
        expect(technical.labels).not_to eq(product.labels)
      end
    end
  end

  describe ".placement" do
    it "answers with where a state belongs" do
      placement = described_class.placement(OpenLanes::Plans.status(:building))

      expect(placement).to have_attributes(type: "started", name: "In Progress")
    end

    # An issue in the wrong column reads exactly like an issue in the right
    # one, so the honest answer to "where does 💩 go" is to decline to say.
    it "declines to place a state whose column is a question about the team, not the plan" do
      aggregate_failures do
        expect(described_class.placement(OpenLanes::Plans.status(:shit))).to be_nil
        expect(described_class.placement(OpenLanes::Plans.status(:rolled_back))).to be_nil
      end
    end

    it "declines to place a state nobody has considered at all" do
      expect(described_class.placement(invented)).to be_nil
    end
  end

  describe ".placement_for" do
    def pull(state)
      OpenLanes::Plans::PullRequest.new(number: "9", title: "t", url: "https://github.com/x/y/pull/9", state:)
    end

    it "gives a unit with no pull requests its plan's own place" do
      placement = described_class.placement_for(OpenLanes::Plans.status(:blocked), [])

      expect(placement).to have_attributes(name: "Todo", labels: %w[blocked])
    end

    # A plan in 🟡 Building has some units merged and some not started;
    # the unit's own pull requests are the better evidence.
    it "puts a unit with an open pull request in review, whatever the plan says" do
      placement = described_class.placement_for(OpenLanes::Plans.status(:new), [pull("Open 🟡")])

      expect(placement).to have_attributes(type: "started", name: "In Review")
    end

    it "marks a unit done once every pull request merged" do
      placement = described_class.placement_for(OpenLanes::Plans.status(:building), [pull("Merged 🟣")])

      expect(placement).to have_attributes(type: "completed", name: "Done")
    end

    # Closed-unmerged is finished business that finished nothing: neither
    # open nor merged, so the evidence is inconclusive and the plan decides.
    it "falls back to the plan when the pull requests were closed without merging" do
      placement = described_class.placement_for(OpenLanes::Plans.status(:building), [pull("Closed 🔴")])

      expect(placement).to have_attributes(type: "started", name: "In Progress")
    end
  end

  describe ".reason_unplaced" do
    it "gives the reason a state was deliberately left out" do
      expect(described_class.reason_unplaced(OpenLanes::Plans.status(:shit))).to include("the plan survives and its pull requests do not")
    end

    # Deliberately left out and never thought about are different problems,
    # and the report should not read the same for both.
    it "says something louder about a state nobody has thought about" do
      expect(described_class.reason_unplaced(invented)).to match(/has ever been decided.*add one to Linear::PLACEMENTS/)
    end
  end

  # @return [OpenLanes::Plans::Status] a sixteenth state, as a future edit would add it
  def invented
    OpenLanes::Plans::Status.new(key: :invented,
      emoji: "🦆",
      label: "Invented",
      requires: [],
      note: "",
      invariant: nil)
  end

  describe ".key!" do
    it "accepts a team key however it was typed" do
      expect(described_class.key!(" tax ")).to eq("TAX")
    end

    it "rejects anything that could never be one, naming what a key looks like" do
      expect { described_class.key!("tax-team") }.to raise_error(OpenLanes::Error, /not a Linear team key.*TAX-41/m)
    end
  end
end

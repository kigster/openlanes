# frozen_string_literal: true

# Backs `/openlanes resync prs` — puts an [NNN.MM] prefix on every pull
# request title that lacks one, and [dev] on the ones that implement no plan.
RSpec.describe OpenLanes::Lifecycle::Resync::Prs, :tree do
  subject(:resync) { described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), github:) }

  # A stand-in for the `gh` CLI. Injected so the suite never touches a real
  # repository or the network.
  let(:github) { instance_double(OpenLanes::Vcs::GitHub, pulls: pulls) }

  let!(:tree) do
    plans do |t|
      t.plan "001.00", :new, "initial-spec", files: { "spec.md" => spec_body }
      t.plan "002.00", :approved, "dev-foundation", prs: [t.merged(2, "Ship it")]
      t.plan "018.01", :approved, "verify-returns", prs: [t.merged(41, "Backfill")]
    end
  end

  let(:changes) { resync.plan }

  def pull(number, title, branch:, files: [])
    { number:, title:, branch:, files:, url: "https://github.com/example/repo/pull/#{number}" }
  end

  describe "#plan" do
    context "when a pull request already carries a prefix" do
      let(:pulls) { [pull(10, "[002.00] Add the thing", branch: "kig/002.00-add")] }

      it "leaves it alone" do
        expect(changes).to be_empty
      end
    end

    context "when the branch names its plan" do
      let(:pulls) { [pull(10, "Add the thing", branch: "kig/002.00-add-the-thing")] }

      it "prefixes the title from the branch" do
        expect(changes.first.new_title).to eq("[002.00] Add the thing")
      end

      it "keeps the pull request number so the edit can be applied" do
        expect(changes.first.number).to eq(10)
      end
    end

    context "when the branch carries a legacy bare number" do
      let(:pulls) { [pull(11, "Older work", branch: "kig/002-older-work")] }

      it "pads it to the canonical shape" do
        expect(changes.first.new_title).to eq("[002.00] Older work")
      end
    end

    context "when the branch names a retroactive plan" do
      let(:pulls) { [pull(12, "Verify against filed returns", branch: "kig/018.01-verify")] }

      it "resolves the decimal slot rather than its whole-number neighbour" do
        expect(changes.first.new_title).to eq("[018.01] Verify against filed returns")
      end
    end

    context "when the branch is silent but the diff touches exactly one plan" do
      let(:pulls) { [pull(13, "Some work", branch: "kig/fix-things", files: [".plans/002.00-✅--dev-foundation/plan.md"])] }

      it "resolves from the diff" do
        expect(changes.first.new_title).to eq("[002.00] Some work")
      end
    end

    context "when the diff touches several plans" do
      let(:pulls) do
        [pull(14,
          "Sweeping change",
          branch: "kig/fix",
          files:  [".plans/001.00-⚪️--initial-spec/spec.md", ".plans/002.00-✅--dev-foundation/plan.md"])]
      end

      # Refusing to pick a winner was honest but useless: the work exists, no
      # plan describes it, and left unnumbered it never appears in the index.
      # So it is given a plan of its own rather than a shrug.
      it "adopts it into a plan of its own rather than flagging it" do
        aggregate_failures do
          expect(changes.first).not_to be_ambiguous
          expect(changes.first).to be_adopted
          expect(changes.first.new_title).to eq("[002.01] Sweeping change")
        end
      end

      it "numbers it after the furthest plan it touches, not the nearest" do
        expect(changes.first.ordinal.to_s).to eq("002.01")
      end

      it "still says why it could not be resolved the ordinary way" do
        expect(changes.first.reason).to match(/none is obviously primary.*adopted into 002\.01/)
      end

      context "with adoption switched off" do
        subject(:resync) do
          described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), github:, adopt: false)
        end

        it "goes back to flagging it for a human" do
          aggregate_failures do
            expect(changes.first).to be_ambiguous
            expect(changes.first.new_title).to be_nil
          end
        end
      end
    end

    context "when nothing resolves — tech debt, CI, a dependency bump" do
      let(:pulls) { [pull(15, "Bump json from 2.21.1 to 2.21.2", branch: "dependabot/bundler/json-2.21.2")] }

      it "proposes [dev], which asserts 'no plan' rather than leaving it ambiguous" do
        expect(changes.first.new_title).to eq("[dev] Bump json from 2.21.1 to 2.21.2")
      end

      it "marks it an assumption, because asserting 'no plan' is the author's call" do
        expect(changes.first).to be_assumed
      end
    end

    context "when a branchless pull request edits a plan's spec" do
      let(:pulls) { [pull(16, "Write it up", branch: "kig/docs", files: [".plans/001.00-⚪️--initial-spec/spec.md"])] }

      it "files it under that plan rather than calling it developer work" do
        expect(changes.first.new_title).to eq("[001.00] Write it up")
      end
    end

    context "when a branch names a plan that does not exist" do
      let(:pulls) { [pull(17, "Typo'd branch", branch: "kig/099.00-nope")] }

      # Nothing in the diff to go on, so it lands after the furthest plan the
      # tree knows about — and takes .02, because .01 is already occupied.
      it "adopts it rather than pointing at a folder that is not there" do
        aggregate_failures do
          expect(changes.first).to be_adopted
          expect(changes.first.ordinal.to_s).to eq("018.02")
        end
      end

      context "with adoption switched off" do
        subject(:resync) do
          described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), github:, adopt: false)
        end

        it "flags it instead of inventing a folder" do
          expect(changes.first).to be_ambiguous
        end
      end
    end
  end

  describe "#call" do
    let(:pulls) { [pull(10, "Add the thing", branch: "kig/002.00-add-the-thing")] }

    it "edits nothing without an explicit commit" do
      expect(github).not_to receive(:retitle)

      resync.call
    end

    it "retitles when committed" do
      expect(github).to receive(:retitle).with(number: 10, title: "[002.00] Add the thing")

      resync.call(commit: true)
    end

    it "never edits a pull request it could not resolve, when it may not adopt" do
      resync = described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), github:, adopt: false)
      allow(github).to receive(:pulls).and_return([pull(14,
        "Sweeping",
        branch: "kig/fix",
        files:  [".plans/001.00-⚪️--initial-spec/spec.md", ".plans/002.00-✅--dev-foundation/plan.md"])])
      expect(github).not_to receive(:retitle)

      resync.call(commit: true)
    end
  end
end

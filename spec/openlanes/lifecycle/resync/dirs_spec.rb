# frozen_string_literal: true

# Backs `/openlanes resync dirs` — reconciles every folder's emoji with
# what the folder actually contains.
RSpec.describe OpenLanes::Lifecycle::Resync::Dirs, :tree do
  subject(:resync) { described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root)) }

  let(:changes) { resync.plan }
  let(:names) { Dir.children(plans_root).sort }

  describe "#plan" do
    context "when every folder's name is already honest" do
      let!(:tree) do
        plans do |t|
          t.plan "001.00", :new, "initial-spec", files: { "spec.md" => spec_body }
          t.plan "002.00", :building, "dev-foundation", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }
          t.plan "003.00", :approved, "ledger", prs: [t.merged(3, "Ship it")]
        end
      end

      it "proposes nothing" do
        expect(changes).to be_empty
      end
    end

    # The dispatcher reconciles names before every dispatch, while agents
    # are running. A folder an agent is inside must keep its name until
    # that agent is done, whatever its contents say by then.
    context "when told to leave a plan alone" do
      let!(:tree) do
        plans do |t|
          t.plan "001.00", :new, "initial-spec", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }
          t.plan "002.00", :new, "second", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }
        end
      end

      it "skips it however wrong its name is" do
        changes = described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), except: ["001.00"]).plan

        expect(changes.map(&:dirname)).to eq(["002.00-⚪️ → second"])
      end
    end

    context "when a folder has outgrown its emoji" do
      let!(:tree) do
        plans do |t|
          t.plan "001.00", :new, "initial-spec", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }
        end
      end

      it "proposes the state the contents justify" do
        expect(changes.map { |c| [c.from, c.to] }).to eq([[:new, :planned]])
      end

      it "keeps the number and the slug, changing only the emoji" do
        expect(File.basename(changes.first.target)).to eq("001.00-⭐️ → initial-spec")
      end
    end

    # `018.09` < `018.1` < `018.10`: one mixed-width folder sorts into the
    # middle of the two-digit range and silently reorders the whole index.
    # That is the entire reason the number is padded, so resync repairs it.
    context "when a folder's number was written before the NNN.MM rule" do
      let!(:tree) do
        plans do |t|
          t.raw "018-⚪️--verify-returns", files: { "spec.md" => spec_body }
        end
      end

      it "pads the number and migrates the separator, leaving the emoji and the slug alone" do
        expect(File.basename(changes.first.target)).to eq("018.00-⚪️ → verify-returns")
      end

      it "does not pretend the state changed" do
        expect(changes.map { |c| [c.from, c.to] }).to eq([[:new, :new]])
      end

      it "says the number was the problem, not the contents" do
        expect(changes.first.reason).to eq("018 is not padded to 018.00")
      end

      it "renames it when committing" do
        resync.call(commit: true)

        expect(names).to eq(["018.00-⚪️ → verify-returns"])
      end
    end

    context "when a retroactive number is written with one digit" do
      let!(:tree) do
        plans do |t|
          t.raw "18.1-⚪️--schedule-k1", files: { "spec.md" => spec_body }
        end
      end

      it "pads both halves" do
        expect(File.basename(changes.first.target)).to eq("018.01-⚪️ → schedule-k1")
      end
    end

    # Both defects at once, repaired as two renames in order: the spelling
    # first, under the status the folder still claims, and only then the
    # status the contents justify — one auditable report line per fact.
    context "when a folder is both unpadded and wearing the wrong emoji" do
      let!(:tree) do
        plans do |t|
          t.raw "007-⚪️--tenancy", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }
        end
      end

      it "migrates the spelling first, then the status" do
        expect(changes.map { |c| File.basename(c.target) })
          .to eq(["007.00-⚪️ → tenancy", "007.00-⭐️ → tenancy"])
      end

      it "chains the status rename off the spelling rename, not the original path" do
        expect(changes.last.source).to eq(changes.first.target)
      end

      it "gives each step its own reason" do
        expect(changes.first.reason).to eq("007 is not padded to 007.00")
        expect(changes.last.reason).to include("contents now justify")
      end

      it "lands on the final name when committed, with no orphan in between" do
        resync.call(commit: true)

        expect(names).to eq(["007.00-⭐️ → tenancy"])
      end
    end

    # The migration path for a tree written entirely in the `--`-era
    # spelling: the status is right, so the spelling rename is the only one.
    context "when a folder's only defect is the old double-dash separator" do
      let!(:tree) do
        plans do |t|
          t.raw "004.00-⚪️--legacy", files: { "spec.md" => spec_body }
        end
      end

      it "proposes exactly one rename, to the arrow spelling" do
        expect(changes.map { |c| File.basename(c.target) }).to eq(["004.00-⚪️ → legacy"])
      end

      it "does not pretend the state changed" do
        expect(changes.map { |c| [c.from, c.to] }).to eq([[:new, :new]])
      end

      it "names the spelling as the reason" do
        expect(changes.first.reason).to eq("name is not in canonical NNN.MM-<emoji> → <slug> form")
      end
    end

    # The same plan written twice — once each way — is a folder collision, and
    # a rename that quietly does nothing would leave the tree misnamed while
    # the report claimed it had been fixed.
    context "when the padded name is already taken by another folder" do
      let!(:tree) do
        plans do |t|
          t.raw "005-⚪️--ledger", files: { "spec.md" => spec_body }
          t.raw "005.00-⚪️--ledger", files: { "spec.md" => spec_body }
        end
      end

      # The unpadded twin sorts first and claims the canonical name; the
      # padded twin's own migration then finds it taken.
      it "refuses rather than silently leaving the folder misnamed" do
        expect { resync.call(commit: true) }.to raise_error(OpenLanes::Error, /005\.00-⚪️--ledger.*already exists/)
      end
    end

    context "when a folder claims Approved & Merged with an open pull request" do
      let!(:tree) do
        plans do |t|
          t.plan "004.00",
            :approved,
            "deploy",
            files: { "spec.md" => spec_body, "plan.md" => "# Plan" },
            prs:   [t.merged(1, "a"), t.open(2, "b")]
        end
      end

      # 🟡 rather than 🔴: an open pull request proves the work is back in the
      # review phase, but nothing on disk says whether a reviewer has seen it,
      # so it lands on the floor of that family.
      it "walks it back to the weakest state the family can prove" do
        expect(changes.map(&:to)).to eq([:building])
      end

      it "records why, so the rename is auditable rather than mysterious" do
        expect(changes.first.reason).to include("1 pull request still open")
      end
    end

    # ⭕️ and 🅱️ share an invariant deliberately; only the folder name says
    # which human must decide, and resync must not overwrite that.
    it "never reclassifies between the two blocked states" do
      plans do |t|
        t.plan "005.00", :blocked, "engine-choice", files: { "blocked.md" => "B1" }
        t.plan "006.00", :product_blocked, "pricing", files: { "blocked.md" => "B1" }
      end

      expect(changes).to be_empty
    end

    # The other half of that rule. The name wins *between* the two blocked
    # states, but neither survives a `blocked.md` with no question left in it.
    # This is how a block drains: `lando-broker` deletes each question as its
    # answer is folded into `spec.md` or `plan.md`, and the pass that empties
    # the file is the pass that moves the folder.
    context "when every question in blocked.md has been answered and folded away" do
      let!(:tree) do
        plans do |t|
          t.plan "005.00",
            :blocked,
            "engine-choice",
            files: { "spec.md" => spec_body, "plan.md" => "# Plan",
                    "blocked.md" => "## Answers\n\n- **B1** \u2014 2026-08-21, CTO: Postgres.\n" }
        end
      end

      it "lets the folder out of Blocked" do
        expect(changes.map { |c| [c.from, c.to] }).to eq([[:blocked, :planned]])
      end

      it "says the file stopped justifying the name, not that the file vanished" do
        expect(changes.first.reason).to include("names no open question")
      end
    end

    it "leaves folders it cannot classify alone rather than guessing" do
      plans { |t| t.plan "007.00", :new, "empty-shell" }

      expect(changes).to be_empty
    end

    it "skips directories that carry no plan number" do
      plans { |t| t.stray("notes") }

      expect(changes).to be_empty
    end
  end

  describe "#call" do
    let!(:tree) do
      plans do |t|
        t.plan "001.00", :new, "initial-spec", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }
      end
    end

    it "changes nothing without an explicit commit" do
      resync.call

      expect(names).to eq(["001.00-⚪️ → initial-spec"])
    end

    it "renames the folder when committed" do
      resync.call(commit: true)

      expect(names).to eq(["001.00-⭐️ → initial-spec"])
    end

    it "preserves the folder's contents across the rename" do
      resync.call(commit: true)

      expect(File.exist?(File.join(plans_root, "001.00-⭐️ → initial-spec", "plan.md"))).to be(true)
    end

    it "reports what it did" do
      expect(resync.call(commit: true).map(&:to)).to eq([:planned])
    end

    it "is idempotent — a second run finds nothing left to do" do
      resync.call(commit: true)

      expect(described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root)).plan).to be_empty
    end
  end
end

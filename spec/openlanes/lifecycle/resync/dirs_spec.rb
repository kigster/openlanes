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
          t.plan "003.00",
            :approved,
            "ledger",
            prs:         [t.merged(3, "Ship it")],
            under:       "archive",
            archived_on: Date.new(2026, 9, 1)
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

        expect(changes.map(&:dirname)).to eq(["002.00━━⚪━━❯second"])
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
        expect(File.basename(changes.first.target)).to eq("001.00━━⭐━━❯initial-spec")
      end
    end

    # `018.09` < `018.1` < `018.10`: one mixed-width folder sorts into the
    # middle of the two-digit range and silently reorders the whole index.
    # That is the entire reason the number is padded, so resync repairs it.
    context "when a folder's number was written before the NNN.MM rule" do
      let!(:tree) do
        plans do |t|
          t.raw "018-⚪--verify-returns", files: { "spec.md" => spec_body }
        end
      end

      it "pads the number and migrates the separator, leaving the emoji and the slug alone" do
        expect(File.basename(changes.first.target)).to eq("018.00━━⚪━━❯verify-returns")
      end

      it "does not pretend the state changed" do
        expect(changes.map { |c| [c.from, c.to] }).to eq([[:new, :new]])
      end

      it "says the number was the problem, not the contents" do
        expect(changes.first.reason).to eq("018 is not padded to 018.00")
      end

      it "renames it when committing" do
        resync.call(commit: true)

        expect(names).to eq(["018.00━━⚪━━❯verify-returns"])
      end
    end

    context "when a retroactive number is written with one digit" do
      let!(:tree) do
        plans do |t|
          t.raw "18.1-⚪--schedule-k1", files: { "spec.md" => spec_body }
        end
      end

      it "pads both halves" do
        expect(File.basename(changes.first.target)).to eq("018.01━━⚪━━❯schedule-k1")
      end
    end

    # Both defects at once, repaired as two renames in order: the spelling
    # first, under the status the folder still claims, and only then the
    # status the contents justify — one auditable report line per fact.
    context "when a folder is both unpadded and wearing the wrong emoji" do
      let!(:tree) do
        plans do |t|
          t.raw "007-⚪--tenancy", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }
        end
      end

      it "migrates the spelling first, then the status" do
        expect(changes.map { |c| File.basename(c.target) })
          .to eq(["007.00━━⚪━━❯tenancy", "007.00━━⭐━━❯tenancy"])
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

        expect(names).to eq(["007.00━━⭐━━❯tenancy"])
      end
    end

    # The migration path for a tree written entirely in the `--`-era
    # spelling: the status is right, so the spelling rename is the only one.
    context "when a folder's only defect is the old double-dash separator" do
      let!(:tree) do
        plans do |t|
          t.raw "004.00-⚪--legacy", files: { "spec.md" => spec_body }
        end
      end

      it "proposes exactly one rename, to the arrow spelling" do
        expect(changes.map { |c| File.basename(c.target) }).to eq(["004.00━━⚪━━❯legacy"])
      end

      it "does not pretend the state changed" do
        expect(changes.map { |c| [c.from, c.to] }).to eq([[:new, :new]])
      end

      it "names the spelling as the reason" do
        expect(changes.first.reason).to eq("name is not in canonical NNN.MM━━<emoji>━━❯<slug> form")
      end
    end

    # The same plan written twice — once each way — is a folder collision, and
    # a rename that quietly does nothing would leave the tree misnamed while
    # the report claimed it had been fixed.
    context "when the padded name is already taken by another folder" do
      let!(:tree) do
        plans do |t|
          t.raw "005-⚪--ledger", files: { "spec.md" => spec_body }
          t.raw "005.00-⚪--ledger", files: { "spec.md" => spec_body }
        end
      end

      # The unpadded twin sorts first and claims the canonical name; the
      # padded twin's own migration then finds it taken.
      it "refuses rather than silently leaving the folder misnamed" do
        expect { resync.call(commit: true) }.to raise_error(OpenLanes::Error, /005\.00-⚪--ledger.*already exists/)
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

    # ⭕ and 🛑 share an invariant deliberately; only the folder name says
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

      expect(names).to eq(["001.00━━⚪━━❯initial-spec"])
    end

    it "renames the folder when committed" do
      resync.call(commit: true)

      expect(names).to eq(["001.00━━⭐━━❯initial-spec"])
    end

    it "preserves the folder's contents across the rename" do
      resync.call(commit: true)

      expect(File.exist?(File.join(plans_root, "001.00━━⭐━━❯initial-spec", "plan.md"))).to be(true)
    end

    it "reports what it did" do
      expect(resync.call(commit: true).map(&:to)).to eq([:planned])
    end

    it "is idempotent — a second run finds nothing left to do" do
      resync.call(commit: true)

      expect(described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root)).plan).to be_empty
    end
  end

  # Decisions N1-N5: names without spaces, single-code-point emoji,
  # inactive plans in dated subfolders. Plain `resync dirs` migrates.
  describe "migrating a repository to the subfolder layout" do
    let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
    let(:resync) { described_class.new(tree:) }
    let(:merged) { "| Pull Request Number | Pull Request Name | Status |\n| -: | :- | -: |\n| 1 | [x](https://github.com/example/repo/pull/1) | Merged 🟣 |\n" }
    let(:top) { Dir.children(plans_root).sort }

    def under(subfolder) = Dir.children(File.join(plans_root, subfolder)).sort

    # Each folder is committed once under a 🟡 name and then renamed to the
    # state it is in, the way the harness moves a plan, so git has a rename
    # to date the archive by.
    before do
      init_repo
      folders = {
        "001-⚪️--old-dashes"        => { "spec.md" => spec_body },
        "002.00-⭕️ → arrow-blocked" => { "blocked.md" => "## B1\n\nWhich?\n" },
        "003.00-✅ → shipped"        => { "pull-requests.md" => merged, "spec.md" => spec_body },
        "004.00-☢️ → parked"        => { "delayed.md" => "Revisit when the API ships.\n" },
        "005.00-❌ → dropped"        => { "discarded.md" => "Not needed.\n" },
        "006.00-🅱️ → product"       => { "blocked.md" => "## B1\n\nWhich colour?\n" }
      }
      plans { |t| folders.each { |name, files| t.raw "#{name[/\A[\d.]+/]}-🟡 → #{name[/[a-z-]+\z/]}", files: } }
      commit_all("old layout", date: "2026-08-01T10:00:00+00:00")
      folders.each_key do |name|
        repo_git("mv", File.join(plans_root, "#{name[/\A[\d.]+/]}-🟡 → #{name[/[a-z-]+\z/]}"), File.join(plans_root, name))
      end
      commit_all("states", date: "2026-09-20T10:00:00+00:00")
    end

    it "previews every rename and move without touching the disk" do
      changes = resync.call

      aggregate_failures do
        expect(changes.map(&:target_name)).to include(
          "001.00━━⚪━━❯old-dashes",
          "002.00━━⭕━━❯arrow-blocked",
          "006.00━━🛑━━❯product",
          "archive/003.00━━✅━━❯[2026-09-20]━━shipped",
          "deferred/004.00━━💤━━❯[2026-09-20]━━parked",
          "abandoned/005.00━━❌━━❯[2026-09-20]━━dropped"
        )
        expect(top).to include("001-⚪️--old-dashes", "003.00-✅ → shipped")
        expect(repo_git("status", "--porcelain")).to eq("")
      end
    end

    it "leaves only open plans at the top level, none with a space, and keeps history" do
      resync.call(commit: true)
      commit_all("migrate")

      aggregate_failures do
        expect(top).to eq(%w[001.00━━⚪━━❯old-dashes 002.00━━⭕━━❯arrow-blocked 006.00━━🛑━━❯product abandoned archive deferred])
        expect(under("archive")).to eq(["003.00━━✅━━❯[2026-09-20]━━shipped"])
        expect(under("deferred")).to eq(["004.00━━💤━━❯[2026-09-20]━━parked"])
        expect(under("abandoned")).to eq(["005.00━━❌━━❯[2026-09-20]━━dropped"])
        expect(repo_git("log", "--follow", "--format=%s", "--", ".plans/archive/003.00━━✅━━❯[2026-09-20]━━shipped/spec.md").lines.map(&:strip))
          .to eq(["migrate", "states", "old layout"])
      end
    end

    it "finds nothing to do on a second run" do
      resync.call(commit: true)

      expect(described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root)).plan).to be_empty
    end

    it "brings a plan that is no longer inactive back to the top, dropping its date" do
      resync.call(commit: true)
      archived = File.join(plans_root, "deferred", "004.00━━💤━━❯[2026-09-20]━━parked")
      revived = File.join(plans_root, "deferred", "004.00━━⚪━━❯[2026-09-20]━━parked")
      File.write(File.join(archived, "spec.md"), spec_body)
      File.delete(File.join(archived, "delayed.md"))
      File.rename(archived, revived)

      changes = described_class.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root)).call(commit: true)

      aggregate_failures do
        expect(changes.map(&:reason)).to include("New is not inactive; back to .plans/")
        expect(top).to include("004.00━━⚪━━❯parked")
        expect(under("deferred")).to be_empty
      end
    end
  end

  describe "a plan with a lock file" do
    let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
    let(:dir) { plans { |t| t.raw "001.00-⚪️ → locked", files: { "spec.md" => spec_body } } && File.join(plans_root, "001.00-⚪️ → locked") }
    let(:lock_file) { File.join(dir, OpenLanes::Plans::Lock::FILENAME) }

    def lock_with(pid:, host: Socket.gethostname)
      File.write(lock_file, JSON.generate(pid:, host:, started_at: "2026-10-13T09:00:00Z"))
    end

    # A pid that cannot be running: spawn a process and reap it.
    def dead_pid = Process.wait(Process.spawn("true"))

    it "keeps its name while this machine's process is alive" do
      lock_with(pid: Process.pid)

      aggregate_failures do
        expect(described_class.new(tree:).call(commit: true)).to be_empty
        expect(File).to exist(lock_file)
      end
    end

    it "clears a lock whose process is gone from this machine, then renames" do
      lock_with(pid: dead_pid)
      described_class.new(tree:).call(commit: true)

      aggregate_failures do
        expect(Dir.children(plans_root)).to eq(["001.00━━⚪━━❯locked"])
        expect(File).not_to exist(File.join(plans_root, "001.00━━⚪━━❯locked", OpenLanes::Plans::Lock::FILENAME))
      end
    end

    it "never clears another machine's lock, and leaves the folder alone" do
      lock_with(pid: dead_pid, host: "elsewhere.example")
      resync = described_class.new(tree:)

      aggregate_failures do
        expect(resync.locks.map(&:foreign?)).to eq([true])
        expect(resync.call(commit: true)).to be_empty
        expect(File).to exist(lock_file)
      end
    end
  end
end

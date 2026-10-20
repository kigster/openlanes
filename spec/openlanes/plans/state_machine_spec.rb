# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::StateMachine do
  # A stand-in for a folder: which files exist, which pull requests it records,
  # and where it was renamed to. The machine asks nothing else of a subject.
  let(:pr_class) { Struct.new(:state) { def open? = state.match?(/open|wip|draft/i) } }

  let(:subject_class) do
    Struct.new(:status, :files, :pull_requests, :renames) do
      def file?(name) = files.key?(name)

      def read(name) = files[name]

      def rename_to(status) = renames << status.key
    end
  end

  def folder(key, files: {}, prs: [])
    subject_class.new(OpenLanes::Plans::STATUS_BY_KEY.fetch(key), files, prs.map { |s| pr_class.new(s) }, [])
  end

  def machine_for(...) = described_class.new(folder(...))

  # A folder far enough along to have pull requests at all.
  def built(key, prs:, files: {})
    folder(key, files: { "spec.md" => "x", "plan.md" => "# y", "pull-requests.md" => "z" }.merge(files), prs:)
  end

  describe "the derived topology" do
    it "reads inbound and outbound off the same declarations, so they cannot disagree" do
      described_class.inbound.each do |to, froms|
        froms.each do |from|
          expect(described_class.outbound(from)).to include(to),
            "expected #{from} -> #{to} to be reachable in both directions"
        end
      end
    end

    it "gives every state exactly one event that reaches it" do
      reachable = OpenLanes::Plans::STATUSES.map(&:key) - [:retroactive]

      expect(described_class.event_for.keys).to match_array(reachable)
    end

    it "gives retroactive no inbound edge, because it is a birth state" do
      expect(described_class.inbound).not_to have_key(:retroactive)
    end

    it "makes discarded the only terminal state and strands nothing else" do
      terminal = OpenLanes::Plans::STATUSES.select(&:terminal?).map(&:key)

      expect(terminal).to eq([:discarded])
    end

    it "lets a release be pulled back out of production" do
      aggregate_failures do
        expect(described_class.edge?(:deployed, :rolled_back)).to be(true)
        expect(described_class.edge?(:rolled_back, :ready_for_review)).to be(true)
        expect(described_class.edge?(:rolled_back, :building)).to be(true)
      end
    end

    it "runs an approved review through 🧪 Verifying, which can still pass or send it back" do
      aggregate_failures do
        expect(described_class.edge?(:in_review, :verifying)).to be(true)
        expect(described_class.edge?(:verifying, :approved)).to be(true)
        expect(described_class.edge?(:verifying, :rejected)).to be(true)
        expect(described_class.event_for.fetch(:verifying)).to eq(:verify)
      end
    end

    it "keeps 🧪 Verifying in the family resync never moves a folder out of" do
      expect(described_class.family_of(:in_review)).to include(:verifying)
    end

    it "lets anything be discarded, from anywhere" do
      others = OpenLanes::Plans::STATUSES.map(&:key) - [:discarded]

      expect(described_class.inbound.fetch(:discarded)).to match_array(others)
    end
  end

  describe "invariants" do
    it "requires the file that proves each phase happened" do
      aggregate_failures do
        expect(OpenLanes::Plans::STATUS_BY_KEY[:new].satisfied_by?(folder(:new))).to be(false)
        expect(OpenLanes::Plans::STATUS_BY_KEY[:new]
          .satisfied_by?(folder(:new, files: { "spec.md" => "x" }))).to be(true)
        expect(OpenLanes::Plans::STATUS_BY_KEY[:planned]
          .satisfied_by?(folder(:planned, files: { "spec.md" => "x" }))).to be(false)
        expect(OpenLanes::Plans::STATUS_BY_KEY[:planned]
          .satisfied_by?(folder(:planned, files: { "spec.md" => "x", "plan.md" => "# y" }))).to be(true)
      end
    end

    it "refuses Approved while a pull request is still open, and says how many" do
      subject = built(:approved, prs: ["Open 🟡", "Merged 🟣"])

      expect(OpenLanes::Plans::STATUS_BY_KEY[:approved].violation(subject)).to eq("Approved & Merged, but 1 pull request still open")
    end

    it "accepts Approved once every pull request is merged" do
      expect(OpenLanes::Plans::STATUS_BY_KEY[:approved]).to be_satisfied_by(built(:approved, prs: ["Merged 🟣"]))
    end

    # 🟢 👀 🔴 all mean "open pull requests exist", and share one invariant so
    # the three cannot drift into disagreeing about what that means.
    it "requires an open pull request for every state in the review phase" do
      aggregate_failures do
        %i[ready_for_review in_review rejected].each do |key|
          status = OpenLanes::Plans::STATUS_BY_KEY.fetch(key)

          expect(status).to be_satisfied_by(built(key, prs: ["Open 🟡"]))
          expect(status.violation(built(key, prs: ["Merged 🟣"]))).to include("already merged")
        end
      end
    end

    it "insists a deferral names its trigger, so deferrals cannot rot quietly" do
      aggregate_failures do
        expect(OpenLanes::Plans::STATUS_BY_KEY[:deferred]
          .satisfied_by?(folder(:deferred, files: { "delayed.md" => "not now" }))).to be(false)
        expect(OpenLanes::Plans::STATUS_BY_KEY[:deferred]
          .satisfied_by?(folder(:deferred, files: { "delayed.md" => "revisit once 018 ships" }))).to be(true)
      end
    end

    # Answers arrive one at a time, so what stops a folder is a question still
    # standing in `blocked.md`, not the file being there. A file holding only
    # the answers already folded into `spec.md` stops nothing.
    it "holds a folder at Blocked only while blocked.md still names a question" do
      aggregate_failures do
        %i[blocked product_blocked].each do |key|
          status = OpenLanes::Plans::STATUS_BY_KEY.fetch(key)
          open = folder(key, files: { "blocked.md" => "### B2. Which rate source?" })
          drained = folder(key, files: { "blocked.md" => "- **B2** \u2014 2026-08-21, CTO: the vendor feed." })

          expect(status).to be_satisfied_by(open)
          expect(status.violation(drained)).to include("names no open question")
        end
      end
    end

    # The clock decides when a plan becomes 💣, and the clock is the sweep's,
    # never the invariant's: asking about a folder must not rename it.
    it "holds a folder at Bomb while blocked.md names a question, and asks nothing of the clock" do
      status = OpenLanes::Plans::STATUS_BY_KEY.fetch(:bomb)

      aggregate_failures do
        expect(status.emoji).to eq("\u{1F4A3}")
        expect(status).to be_satisfied_by(folder(:bomb, files: { "blocked.md" => "## B1 Which feed?" }))
        expect(status).not_to be_satisfied_by(folder(:bomb))
        expect(status.violation(folder(:bomb, files: { "blocked.md" => "- **B1** \u2014 answered" })))
          .to include("names no open question")
      end
    end

    it "stops a folder being Retroactive once it has been documented" do
      subject = folder(:retroactive, files: { "spec.md" => "written up" }, prs: ["Merged 🟣"])

      expect(OpenLanes::Plans::STATUS_BY_KEY[:retroactive].violation(subject)).to include("already exists")
    end
  end

  describe "the bomb" do
    let(:question) { { "spec.md" => "x", "blocked.md" => "## B1 Which feed?" } }

    it "is entered from either block, and from nothing else" do
      expect(described_class.inbound.fetch(:bomb)).to match_array(%i[blocked product_blocked])
    end

    it "fires from a technical block and from a product block" do
      %i[blocked product_blocked].each do |key|
        subject = folder(key, files: question)

        expect(described_class.new(subject).promote!(:bomb).key).to eq(:bomb)
        expect(subject.renames).to eq([:bomb])
      end
    end

    it "leaves back through the block its blocked.md describes" do
      aggregate_failures do
        expect(described_class.edge?(:bomb, :blocked)).to be(true)
        expect(described_class.edge?(:bomb, :product_blocked)).to be(true)
        expect(described_class.new(folder(:bomb, files: question)).promote!(:blocked).key).to eq(:blocked)
      end
    end

    it "resumes the normal path once its questions are answered, as a block does" do
      expect(described_class.outbound(:bomb)).to include(:researched, :planned, :building)
    end

    it "is settled, so no agent is assigned to it, and shares the blocked family" do
      aggregate_failures do
        expect(described_class::SETTLED).to include(:bomb)
        expect(described_class::FAMILIES.first).to eq(%i[blocked product_blocked bomb])
      end
    end

    it "never defers: an aging sweep halts on it instead" do
      expect(described_class.edge?(:bomb, :deferred)).to be(false)
    end
  end

  describe "#allowed" do
    it "offers the next spine state once its guard is satisfied" do
      machine = machine_for(:new, files: { "spec.md" => "x", "plan.md" => "# y" })

      expect(machine.allowed).to include(:planned)
    end

    it "offers only 📋 while plan.md is still blank" do
      machine = machine_for(:new, files: { "spec.md" => "x", "plan.md" => "" })

      expect(machine.allowed).to include(:ready_for_planning)
      expect(machine.allowed).not_to include(:planned)
    end

    it "withholds it while the guard fails" do
      machine = machine_for(:new, files: { "spec.md" => "x" })

      expect(machine.allowed).not_to include(:planned)
    end

    it "never offers a state the topology does not reach, however well its guard passes" do
      machine = described_class.new(built(:new, prs: ["Merged 🟣"]))

      expect(machine.allowed).not_to include(:approved)
    end
  end

  describe "#promote!" do
    it "walks the spine when given no destination, and renames the folder" do
      subject = folder(:new, files: { "spec.md" => "# S\n\n## Research\n\nWhat was found." })

      expect(described_class.new(subject).promote!.key).to eq(:researched)
      expect(subject.renames).to eq([:researched])
    end

    # The only fact on disk separating 🔎 Researched from ⚪️ New. Without it
    # the two states are the same folder wearing different names, and the
    # relay that keeps yoda-writer off unresearched specifications collapses.
    it "refuses to call a specification researched when nobody has researched it" do
      subject = folder(:new, files: { "spec.md" => "# S\n\n## Goal\n\nShip it." })

      expect { described_class.new(subject).promote! }.to raise_error(described_class::Refused, /no `## Research` chapter/)
    end

    it "moves to a named destination off the spine" do
      subject = folder(:new, files: { "spec.md" => "x", "blocked.md" => "B1" })

      expect(described_class.new(subject).promote!(:blocked).key).to eq(:blocked)
      expect(subject.renames).to eq([:blocked])
    end

    # A refusal is information: it says the phase has not actually happened.
    it "refuses with the destination's own violation when the guard fails" do
      subject = folder(:new, files: { "spec.md" => "x" })

      expect { described_class.new(subject).promote!(:planned) }.to raise_error(described_class::Refused, /Planned requires `plan.md`/)
      expect(subject.renames).to be_empty
    end

    it "refuses with the edge itself when the topology has no such move" do
      subject = built(:new, prs: ["Merged 🟣"])

      expect { described_class.new(subject).promote!(:approved) }.to raise_error(described_class::Refused, /New cannot become .*Approved & Merged/)
    end

    it "says so plainly at a terminal state" do
      expect { machine_for(:discarded, files: { "discarded.md" => "no" }).promote! }.to raise_error(described_class::Refused, /terminal/)
    end

    # Not straight to 🟢. Building is two halves, and a change request reopens
    # both: the fix goes back through 🎨 so neither half is assumed to still
    # hold just because nobody complained about it.
    it "walks 🔴 back through 🎨 rather than skipping the reviewer" do
      subject = built(:rejected, prs: ["Open 🟡"])

      expect(described_class.new(subject).promote!.key).to eq(:building_ui)
    end

    it "sends a review that found slop to 💩, keeping the plan and dropping the work" do
      subject = built(:in_review, files: { "rewrite.md" => "start over" }, prs: ["Open 🟡"])

      expect(described_class.new(subject).promote!(:shit).key).to eq(:shit)
    end
  end

  # The one move backwards, behind a person's discard (W9).
  describe "#retreat!" do
    let(:planned_files) { { "spec.md" => "x", "plan.md" => "# Plan\n\n## Unit 1\n" } }
    let(:building) { folder(:building, files: planned_files) }

    it "steps back one state along the spine, and renames the folder" do
      aggregate_failures do
        expect(described_class.new(building).retreat!.key).to eq(:planned)
        expect(building.renames).to eq([:planned])
      end
    end

    it "derives every step back from the spine, as far as verification" do
      expect(described_class::RETREAT).to eq(researched: :new,
        ready_for_planning: :researched,
        planned: :ready_for_planning,
        building: :planned,
        building_ui: :building,
        ready_for_review: :building_ui,
        in_review: :ready_for_review,
        verifying: :in_review)
    end

    it "refuses with the earlier state's own violation when the folder does not fit it" do
      expect { described_class.new(built(:building, prs: ["Open 🟡"])).retreat! }
        .to raise_error(described_class::Refused, /Planned, but 1 pull request/)
    end

    it "refuses a state with nothing behind it" do
      expect(machine_for(:rejected).retreat_refusal).to eq("🔴 Changes Requested has no state behind it to go back to")
    end

    it "is not a way forward: may? and the derived topology never see it" do
      aggregate_failures do
        expect(described_class.new(building).may?(:planned)).to be(false)
        expect(described_class.inbound.fetch(:planned)).not_to include(:building)
      end
    end
  end

  describe "#spine_next" do
    it "walks spec → plan → build → review → verify → merge → ship" do
      expected = {
        retroactive: :planned, new: :researched, researched: :ready_for_planning, ready_for_planning: :planned,
        planned: :building, building: :building_ui, building_ui: :ready_for_review,
        ready_for_review: :in_review, in_review: :verifying, verifying: :approved, approved: :deployed,
        rejected: :building_ui, rolled_back: :ready_for_review, shit: :planned,
        discarded: nil, blocked: nil, deployed: nil
      }

      aggregate_failures do
        expected.each { |from, to| expect(machine_for(from).spine_next).to eq(to), "#{from} -> #{to}" }
      end
    end
  end

  describe "#best_fit" do
    it "picks the furthest state along the spine that the contents justify" do
      machine = described_class.new(built(:retroactive, prs: ["Merged 🟣"]))

      expect(machine.best_fit.key).to eq(:approved)
    end

    # ⭐️ and 🟡 are told apart only by the agent that renamed the folder
    # when it started, so a resync must leave a ⭐️ folder where it is.
    it "leaves a Planned folder at Planned; only an agent starting moves it to Building" do
      machine = machine_for(:planned, files: { "spec.md" => "x", "plan.md" => "# y" })

      expect(machine.best_fit.key).to eq(:planned)
    end

    # If Building required a pull request to be entered, nothing could ever
    # justify entering it. A pull request is opened once, when the second
    # implementer advances the plan out of 🎨, and neither implementer gets
    # a turn without the folder already being in a building state.
    it "does not require a pull request to stay at Building" do
      machine = machine_for(:building, files: { "spec.md" => "x", "plan.md" => "# y" })

      expect(machine.best_fit.key).to eq(:building)
    end

    it "prefers a block over spine progress, because a block is the louder fact" do
      machine = machine_for(:building, files: { "spec.md" => "x", "plan.md" => "# y", "blocked.md" => "B1" })

      expect(machine.best_fit.key).to eq(:blocked)
    end

    it "leaves a folder alone when its current status already holds, and nothing further is justified" do
      machine = machine_for(:new, files: { "spec.md" => "x" })

      expect(machine.best_fit.key).to eq(:new)
    end

    # ⭕️ and 🅱️ share an invariant on purpose: both mean "a human must
    # decide", and only the folder name says which human. Nothing may re-derive
    # that from the contents, or every ⭕️ silently becomes 🅱️.
    it "never reclassifies between the two blocked states" do
      aggregate_failures do
        %i[blocked product_blocked].each do |key|
          expect(machine_for(key, files: { "blocked.md" => "B1. Who decides?" }).best_fit.key).to eq(key)
        end
      end
    end

    it "never reclassifies within the review phase, which disk contents cannot tell apart" do
      aggregate_failures do
        %i[planned building building_ui ready_for_review in_review rejected].each do |key|
          expect(described_class.new(built(key, prs: ["Open 🟡"])).best_fit.key).to eq(key)
        end
      end
    end

    # 🎨 looks exactly like 🟡 on disk: spec.md, plan.md, and no pull request
    # yet. Left out of the family, every resync renamed a folder an
    # implementer had just moved to 🎨 straight back to 🟡, and the hand-off
    # to the front-end half never happened.
    it "never reclassifies Building UI back to Building, which its contents cannot distinguish" do
      machine = machine_for(:building_ui, files: { "spec.md" => "x", "plan.md" => "# y" })

      expect(machine.best_fit.key).to eq(:building_ui)
    end

    # A state missing from the preference order can never be chosen on
    # purpose, only fall out as the first fit; that is how 🎨 went missing.
    it "ranks every state, so none is reachable only by accident" do
      expect(OpenLanes::Plans::STATUSES.map(&:key) - described_class::PREFERENCE).to be_empty
    end

    # Arriving from outside the family, the contents prove only its floor.
    it "lands on the family's weakest member when a folder falls back into it" do
      machine = described_class.new(built(:approved, prs: ["Merged 🟣", "Open 🟡"]))

      expect(machine.best_fit.key).to eq(:building)
    end
  end

  describe "OpenLanes.status" do
    it "resolves a state by its key and by its emoji" do
      aggregate_failures do
        expect(OpenLanes::Plans.status(:building).label).to eq("Building")
        expect(OpenLanes::Plans.status("⚪️").key).to eq(:new)
        expect(OpenLanes::Plans.status("⚪").key).to eq(:new)
      end
    end

    # The synonym table that used to live here rotted: six of its words pointed
    # at a state that had been renamed out of existence.
    it "resolves nothing else, because a state has exactly two names" do
      aggregate_failures do
        %w[white star yellow green complete completed done wip ready aborted nonsense].each do |word|
          expect(OpenLanes::Plans.status(word)).to be_nil, "expected #{word.inspect} not to resolve"
        end
      end
    end
  end

  describe "📋 Ready for Planning" do
    it "sits on the spine between researched and planned" do
      expect(described_class::SPINE[:researched]).to eq(:ready_for_planning)
      expect(described_class::SPINE[:ready_for_planning]).to eq(:planned)
    end

    it "is justified by a spec and a plan.md that holds no plan yet", :tree do
      path = plans { |t|
        t.plan "020.00",
          :researched,
          "qualified",
          files: {
            "spec.md" => "#{spec_body}\n## Research\n\nFound.\n", "plan.md" => ""
          }
      }
      subject = OpenLanes::Plans::Tree.new(dir: path).subjects.first
      expect(subject.best_fit.key).to eq(:ready_for_planning)
    end

    it "does not let a blank plan.md pass for ⭐️ Planned", :tree do
      path = plans { |t| t.plan "020.00", :planned, "qualified", files: { "spec.md" => spec_body, "plan.md" => "" } }
      subject = OpenLanes::Plans::Tree.new(dir: path).subjects.first
      expect(subject.violation).to include("plan.md", "no work units")
    end

    it "treats a plan.md holding only a ledger note as still blank", :tree do
      note = OpenLanes::Plans::Ledger.block("> [2026-09-04 11:29:20 AM PDT] [ agent: luthen-rael-planner   status: Started, round 1 ]")
      path = plans { |t| t.plan "020.00", :ready_for_planning, "q", files: { "spec.md" => spec_body, "plan.md" => note } }
      subject = OpenLanes::Plans::Tree.new(dir: path).subjects.first
      expect(subject.best_fit.key).to eq(:ready_for_planning)
    end

    it "becomes ⭐️ once plan.md has a heading", :tree do
      path = plans { |t| t.plan "020.00", :ready_for_planning, "q", files: { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## Unit 1\n" } }
      subject = OpenLanes::Plans::Tree.new(dir: path).subjects.first
      expect(subject.best_fit.key).to eq(:planned)
    end

    # The 020.00 transcript: yoda finished, the folder was renamed forward,
    # and the resync renamed it straight back because nothing could enter
    # ⭐️ without a plan.md that only luthen-rael writes. With 📋 between them
    # the resync leaves yoda's work standing.
    it "keeps a folder yoda finished at 📋 through a resync", :tree do
      path = plans { |t|
        t.plan "020.00",
          :ready_for_planning,
          "qualified-at",
          files: {
            "spec.md" => "#{spec_body}\n## Research\n\nFound.\n\n## Goal\n\nShip.\n", "plan.md" => ""
          }
      }
      tree = OpenLanes::Plans::Tree.new(dir: path)
      OpenLanes::Lifecycle::Resync::Dirs.new(tree:).call(commit: true)
      expect(tree.reload.subjects.first.status.key).to eq(:ready_for_planning)
    end

    it "lets the pair submit straight from 🟡 and from 🔴" do
      expect(described_class.inbound[:ready_for_review]).to include(:building, :rejected, :building_ui)
    end
  end
end

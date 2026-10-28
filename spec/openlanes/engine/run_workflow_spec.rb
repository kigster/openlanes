# frozen_string_literal: true

# `openlanes run` as a workflow: no dry-cli command, no exit. Every example
# runs `--isolation shared` on a bare temp tree, with the live board's Redis
# and the control room replaced, so nothing here reaches a network or
# spawns an agent CLI.
RSpec.describe OpenLanes::Engine::RunWorkflow, :tree do
  let(:tree) { OpenLanes::Plans.tree(plans_root) }

  before do
    allow(OpenLanes::Engine::Runner).to receive(:new).and_wrap_original do |original, **keywords|
      # The temp project has no desired_codebase_quality:, whose gate
      # (plan 035, dispatcher_quality_gate_spec) would hold every plan.
      original.call(**keywords, sleeper: ->(_) {}, quality_gate: nil)
    end
    allow(OpenLanes::Live).to receive(:connect).and_return(OpenLanes::Live.memory_store)
    plans { |t| t.plan("001.00", :building, "tax-rule-dsl", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }) }
  end

  def workflow(**)
    described_class.new(tree:,
      isolation: "shared",
      dry_run: true,
      plan: "001",
      log: File.join(plans_root, "..", "progress.log"),
**)
  end

  # STDOUT and STDERR captured apart, with the result the workflow answered.
  def call(**)
    out = CapturedStream.new
    err = CapturedStream.new
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    result = workflow(**).call
    [result, strip_ansi(out.string), strip_ansi(err.string)]
  ensure
    $stdout, $stderr = original_out, original_err
  end

  # Plan 031, D12: what the live board's probes said decides which adapters are dealt.
  describe "the adapters reviewers may be dealt" do
    let(:probed) do
      [OpenLanes::Adapters::Availability.up("claude", [], Time.now),
       OpenLanes::Adapters::Availability.down("codex", "not signed in", Time.now)]
    end
    let(:live) { instance_double(OpenLanes::Live::Session, probes: instance_double(OpenLanes::Adapters::Probes, current: probed)) }

    def usable(live) = workflow.send(:usable_for, live)

    it "skips one the probe found down, and keeps one it has not probed" do
      expect(%w[claude codex gemini].map { usable(live).call(it) }).to eq([true, false, true])
    end

    it "deals every adapter without a live board, which has no probe" do
      expect(usable(nil)).to be(OpenLanes::Agents::Dealing::ANY)
    end
  end

  describe "refusals, before anything is set up" do
    {
      "--prompt without --agent"        => [{ prompt: "be brief" }, 64, "--prompt only works with --agent"],
      "an unknown --agent"              => [{ agent: "nobody" }, 65, "No agent called nobody"],
      "an unknown --skip"               => [{ skip: "nobody" }, 65, "No agent called nobody"],
      "--agent and --skip the same"     => [{ agent: "backend-coder", skip: "backend-coder" }, 64, "contradict each other"],
      "an unknown --plan"               => [{ plan: "999" }, 66, "No plan 999"],
      "an --agent no plan is ready for" => [{ agent: "spec-writer" }, 65, "backend-coder takes it"],
      "worktree isolation, no git"      => [{ isolation: "worktree" }, 66, "is not a git repository"]
    }.each do |label, (options, status, phrase)|
      it "fails with #{status} for #{label}" do
        result, = call(**options)

        expect([result.failure.status, result.failure.message]).to match([status, a_string_including(phrase)])
      end
    end
  end

  it "previews a dry run, answering 0 with the agent it would invoke" do
    result, out, err = call

    aggregate_failures do
      expect(result.value!).to eq(0)
      expect(out).to include("001.00  backend-coder")
      expect(err).to include("Dry run")
    end
  end

  it "answers 1 when an attempt failed" do
    executor = instance_double(OpenLanes::Execution::Executor)
    allow(executor).to receive(:call).and_return(
      OpenLanes::Execution::Executor::Result.new(ok: false,
        note: "claude exited 1",
        up: 0,
        down: 0,
        subagents: 0,
        delegated: 0,
        seconds: 0.0)
    )
    allow(OpenLanes::Execution::Executor).to receive(:new).and_return(executor)

    expect(call(dry_run: false, rounds: 1).first.value!).to eq(1)
  end

  # Plan 035: a real run holds every plan while the key is missing, so its
  # agent is never called.
  it "holds a real run while desired_codebase_quality is missing" do
    gates = []
    allow(OpenLanes::Engine::Runner).to receive(:new).and_wrap_original do |original, **keywords|
      gates << keywords[:quality_gate]
      original.call(**keywords, sleeper: ->(_) {})
    end
    executor = instance_double(OpenLanes::Execution::Executor, call: nil)
    allow(OpenLanes::Execution::Executor).to receive(:new).and_return(executor)

    call(dry_run: false, rounds: 1)
    aggregate_failures do
      expect(executor).not_to have_received(:call)
      expect(gates.last.call).to be(true)
    end
  end

  # Moved here from run_spec.rb with the method it tests.
  describe "the publisher" do
    subject(:publisher) { workflow(**options).send(:publisher_for, plans_root, :worktree) }

    context "with the default options" do
      let(:options) { { dry_run: false } }

      it { is_expected.to be_a(OpenLanes::Vcs::Publisher) }
    end

    context "with --no-git-push" do
      let(:options) { { dry_run: false, git_push: false } }

      it { is_expected.to be_nil }
    end
  end

  # Verification, the arbitrator, merging and upkeep all act on GitHub, so
  # they come up only where the run publishes: a worktree and a publisher.
  describe "what a published run brings up" do
    subject(:built) { %i[verification_for arbitration_for merging_for upkeep_for].map { flow.send(it, publisher, worktree) } }

    let(:flow) { workflow(dry_run: false) }
    let(:publisher) { instance_double(OpenLanes::Vcs::Publisher) }
    let(:worktree) { instance_double(OpenLanes::Vcs::Worktree) }

    before { allow(OpenLanes::Vcs).to receive(:github).and_return(instance_double(OpenLanes::Vcs::GitHub)) }

    it "builds all four" do
      expect(built).to match([an_instance_of(OpenLanes::Engine::Verification::Driver), an_instance_of(OpenLanes::Engine::Arbitration),
                              an_instance_of(OpenLanes::Engine::Merging), be_truthy])
    end

    context "without a worktree" do
      let(:worktree) { nil }

      it { is_expected.to eq([nil, nil, nil, nil]) }
    end
  end

  # R4 on the terminal (plan 035): a person there is asked, and the answer
  # is written to .openlanes.yml before any agent starts.
  describe "asking the quality on a terminal" do
    subject(:asked) { workflow(dry_run: false).send(:ask_quality) }

    let(:prompt) { instance_double(TTY::Prompt, select: :high) }

    before do
      allow($stdin).to receive(:tty?).and_return(true)
      allow($stderr).to receive(:tty?).and_return(true)
      allow(TTY::Prompt).to receive(:new).and_return(prompt)
      allow(OpenLanes::Engine::QualityQuestion).to receive(:settle!)
      asked
    end

    it "settles the answer as openlanes run" do
      expect(OpenLanes::Engine::QualityQuestion).to have_received(:settle!).with(hash_including(quality: :high, by: "openlanes run"))
    end
  end

  # R3: once per run, before any pull request is labelled.
  describe "the review label sync" do
    let(:sync) { instance_double(OpenLanes::Vcs::LabelSync) }
    let(:create) do
      OpenLanes::Vcs::LabelSync::Change.new(label: OpenLanes::Plans::ReviewLabel::APPROVED, action: :create, was: nil)
    end
    let(:keep) do
      OpenLanes::Vcs::LabelSync::Change.new(label: OpenLanes::Plans::ReviewLabel::INITIAL, action: :keep, was: "c2e0c6")
    end

    let(:migration) { instance_double(OpenLanes::Vcs::LabelMigration) }
    let(:nothing_owed) { OpenLanes::Vcs::LabelMigration::Outcome.new(pending: false, moves: {}) }

    before do
      allow(OpenLanes::Vcs).to receive_messages(label_sync: sync, label_migration: migration)
      allow(sync).to receive(:call).and_return([keep, create])
      allow(migration).to receive(:call).and_return(nothing_owed)
    end

    # Calls the private step the way #prepare does, capturing STDERR.
    def sync_with(migrated: nil, **)
      err = CapturedStream.new
      original, $stderr = $stderr, err
      workflow(isolation: "worktree", **).send(:sync_labels, migrated)
      strip_ansi(err.string)
    ensure
      $stderr = original
    end

    # Calls the startup step the way #call does: its result, and STDERR.
    def migrate_with(**)
      err = CapturedStream.new
      original, $stderr = $stderr, err
      [workflow(isolation: "worktree", **).send(:labels_migrated), strip_ansi(err.string)]
    ensure
      $stderr = original
    end

    it "runs only when the run opens pull requests" do
      aggregate_failures do
        expect(workflow(isolation: "worktree").send(:publishing?)).to be(true)
        expect(workflow(isolation: "worktree", git_push: false).send(:publishing?)).to be(false)
        expect(workflow.send(:publishing?)).to be(false)
      end
    end

    it "is not asked for on a shared-tree run" do
      call
      expect(OpenLanes::Vcs).not_to have_received(:label_sync)
    end

    it "previews the labels it would write under a dry run" do
      err = sync_with(dry_run: true)

      aggregate_failures do
        expect(sync).to have_received(:call).with(dry_run: true)
        expect(err).to include("Dry run: would sync review labels", "create review-approved (#109a10)")
        expect(err).not_to include("keep ready-for-review")
      end
    end

    it "reports the labels it wrote" do
      expect(sync_with(dry_run: false)).to include("Synced review labels")
    end

    it "says nothing when every label was already right" do
      allow(sync).to receive(:call).and_return([keep])

      expect(sync_with(dry_run: false)).to be_empty
    end

    # Copilot on #69: `gh` with no -R resolves the repository from the
    # directory it runs in, so the sync must run in --root's checkout.
    it "syncs the repository --root names, not the current directory's" do
      elsewhere = Dir.mktmpdir("openlanes-root")
      sync_with(dry_run: true, root: elsewhere)

      expect(OpenLanes::Vcs).to have_received(:label_sync).with(root: elsewhere)
    ensure
      FileUtils.rm_rf(elsewhere)
    end

    it "says which pull requests the migration moved, beside the labels it synced" do
      moved = OpenLanes::Vcs::LabelMigration::Outcome.new(pending: true, moves: { OpenLanes::Vcs::LabelMigration::STEPS.first => [7, 9] })

      expect(sync_with(dry_run: false, migrated: moved)).to include("relabel ready-to-merge → review-approved on #7, #9")
    end

    # R3 and Copilot on #78: verifier trusts `ready-to-merge`, so a publishing
    # run must not start while an M3 one could still be on an open PR.
    describe "the migration of M3's labels" do
      it "runs before the run starts, against --root's repository" do
        result, = migrate_with(dry_run: false)

        aggregate_failures do
          expect(result.value!).to eq(nothing_owed)
          expect(migration).to have_received(:call).with(dry_run: false)
          expect(OpenLanes::Vcs).to have_received(:label_migration).with(root: plans_root.sub(%r{/\.plans\z}, ""))
        end
      end

      it "refuses to start a publishing run it could not finish, so the next start migrates again" do
        allow(migration).to receive(:call).and_raise(OpenLanes::Error, "could not label #7: HTTP 502")
        result, = migrate_with(dry_run: false)

        aggregate_failures do
          expect(result.failure.status).to eq(69)
          expect(result.failure.message).to include("Review labels not migrated: could not label #7: HTTP 502", "--no-git-push")
        end
      end

      it "only warns under a dry run, which labels nothing" do
        allow(migration).to receive(:call).and_raise(OpenLanes::Error, "could not list labels: HTTP 401")
        result, err = migrate_with(dry_run: true)

        aggregate_failures do
          expect(result.value!).to be_nil
          expect(err).to include("Review labels not migrated: could not list labels: HTTP 401")
        end
      end

      it "is not asked for when the run opens no pull requests" do
        result, = migrate_with(dry_run: false, git_push: false)

        aggregate_failures do
          expect(result.value!).to be_nil
          expect(OpenLanes::Vcs).not_to have_received(:label_migration)
        end
      end
    end

    it "warns and goes on when gh cannot be reached" do
      allow(sync).to receive(:call).and_raise(OpenLanes::Error, "could not list labels: HTTP 401")

      expect(sync_with(dry_run: false)).to include("Review labels not synced: could not list labels: HTTP 401")
    end
  end
end

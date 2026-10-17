# frozen_string_literal: true

# `openlanes run` as a workflow: no dry-cli command, no exit. Every example
# runs `--isolation shared` on a bare temp tree, with the live board's Redis
# and the control room replaced, so nothing here reaches a network or
# spawns an agent CLI.
RSpec.describe OpenLanes::Engine::RunWorkflow, :tree do
  let(:tree) { OpenLanes::Plans.tree(plans_root) }

  before do
    allow(OpenLanes::Engine::Runner).to receive(:new).and_wrap_original do |original, **keywords|
      original.call(**keywords, sleeper: ->(_) {})
    end
    allow(OpenLanes::Live).to receive(:connect).and_return(OpenLanes::Live.memory_store)
    plans { |t| t.plan("001.00", :building, "tax-rule-dsl", files: { "spec.md" => spec_body, "plan.md" => "# Plan" }) }
  end

  def workflow(**)
    described_class.new(tree:,
      isolation: "shared",
      dry_run: true,
      until_settled: true,
      web: false,
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

  describe "refusals, before anything is set up" do
    {
      "--prompt without --agent"        => [{ prompt: "be brief" }, 64, "--prompt only works with --agent"],
      "an unknown --agent"              => [{ agent: "nobody" }, 65, "No agent called nobody"],
      "an unknown --skip"               => [{ skip: "nobody" }, 65, "No agent called nobody"],
      "--agent and --skip the same"     => [{ agent: "luke-backend", skip: "luke-backend" }, 64, "contradict each other"],
      "an unknown --plan"               => [{ plan: "999" }, 66, "No plan 999"],
      "an --agent no plan is ready for" => [{ agent: "yoda-writer" }, 65, "luke-backend takes it"],
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
      expect(out).to include("001.00  luke-backend")
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

  # R3: once per run, before any pull request is labelled.
  describe "the review label sync" do
    let(:sync) { instance_double(OpenLanes::Vcs::LabelSync) }
    let(:create) do
      OpenLanes::Vcs::LabelSync::Change.new(label: OpenLanes::Plans::ReviewLabel::APPROVED, action: :create, was: nil)
    end
    let(:keep) do
      OpenLanes::Vcs::LabelSync::Change.new(label: OpenLanes::Plans::ReviewLabel::INITIAL, action: :keep, was: "c2e0c6")
    end

    before do
      allow(OpenLanes::Vcs).to receive(:label_sync).and_return(sync)
      allow(sync).to receive(:call).and_return([keep, create])
    end

    # Calls the private step the way #prepare does, capturing STDERR.
    def sync_with(**)
      err = CapturedStream.new
      original, $stderr = $stderr, err
      workflow(isolation: "worktree", **).send(:sync_labels)
      strip_ansi(err.string)
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

    it "warns and goes on when gh cannot be reached" do
      allow(sync).to receive(:call).and_raise(OpenLanes::Error, "could not list labels: HTTP 401")

      expect(sync_with(dry_run: false)).to include("Review labels not synced: could not list labels: HTTP 401")
    end
  end
end

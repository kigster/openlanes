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
end

# frozen_string_literal: true

# `openlanes unblock` as a workflow: no dry-cli command, no exit. The answer is
# the exit status the command would end with, or the refusal it would print.
RSpec.describe OpenLanes::Lifecycle::UnblockWorkflow, :tree do
  let(:blocked_body) do
    <<~MARKDOWN
      # Blocked

      ## B1. Which vendor

      ## A1. The cheaper one

      Decided by Ada Example <ada@example.com>, 2026-08-01.
    MARKDOWN
  end

  let(:folder) { Dir.children(plans_root).find { it.start_with?("001.00") } }

  before do
    plans do |t|
      t.plan("001.00", :blocked, "vendor-choice", files: { "spec.md" => spec_body, "blocked.md" => blocked_body })
      t.plan("002.00", :new, "unstopped", files: { "spec.md" => spec_body })
    end
  end

  def workflow(**)
    described_class.new(tree: OpenLanes::Plans.tree(plans_root), root: File.dirname(plans_root), **)
  end

  # STDOUT and STDERR, captured apart, with the result the workflow answered.
  def drain(*tokens, **)
    out = CapturedStream.new
    err = CapturedStream.new
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    result = workflow(**).call(tokens)
    [result, strip_ansi(out.string), strip_ansi(err.string)]
  ensure
    $stdout, $stderr = original_out, original_err
  end

  # The agent "folds" A1 by retiring blocked.md, the way lando-broker does.
  def with_executor
    executor = instance_double(OpenLanes::Execution::Executor)
    allow(executor).to receive(:call) do |_agent, subject, **|
      FileUtils.rm_f(File.join(subject.feature.path, "blocked.md"))
      [true, "completed"]
    end
    allow(OpenLanes::Execution::Executor).to receive(:new).and_return(executor)
  end

  it "fails with a status-65 refusal naming the known agents for an unknown agent" do
    result, = drain("001", agent: "nobody")

    expect([result.failure.status, result.failure.message]).to match([65, a_string_including("No agent called nobody", "lando-broker")])
  end

  it "answers 66 for a number with no folder, and names it on STDOUT" do
    result, out, = drain("999", dry_run: true)

    expect([result.value!, out]).to match([66, a_string_including("999\tunknown\t0 open\tno plan of that number")])
  end

  it "answers 65 for a folder that was never blocked" do
    result, = drain("002", dry_run: true)

    expect(result.value!).to eq(65)
  end

  it "previews a dry run, changes nothing and answers 0" do
    result, out, err = drain("001", dry_run: true)

    aggregate_failures do
      expect(result.value!).to eq(0)
      expect(out).to include("001.00\tblocked\t1 open\tnot attempted")
      expect(unwrapped(err)).to include("B1. Which vendor", "Dry run: no agent was invoked")
      expect(File).to exist(File.join(plans_root, folder, "blocked.md"))
    end
  end

  it "hands the plan to the agent and reports the block retired" do
    with_executor
    result, out, err = drain("001")

    aggregate_failures do
      expect(result.value!).to eq(0)
      expect(out).to include("blocked.md retired")
      expect(unwrapped(err)).to include("1 question folded in", "1 plan out of the block")
    end
  end
end

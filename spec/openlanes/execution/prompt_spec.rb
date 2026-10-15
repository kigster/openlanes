# frozen_string_literal: true

# The executor's specs read the prompt through the argv. These build one
# directly, which is the point of it being its own object: what an agent is
# told can be checked without a process, an executor or an adapter's flags.
RSpec.describe OpenLanes::Execution::Prompt, :tree do
  subject(:text) do
    described_class.new(agent:,
      subject: plan,
      root: "/repo",
      profile:,
      round: 3,
      successor: "hansolo-reviewer",
      max_tokens: 1000,
      seconds: 120,
      denied: ["git push"],
      granted: ["gh pr review"]).to_s
  end

  let(:agent) { OpenLanes::Agents.find("r2d2-mechanic") }
  let(:profile) { OpenLanes::Agents::Profile.resolve(agent) }
  let(:plan) do
    plans { |t| t.plan "001.00", :building, "task", files: { "spec.md" => spec_body, "plan.md" => "## Task\n" } }
    OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
  end

  it "tells an agent in a worktree that its checkout's .plans is a snapshot" do
    expect(text).to include("snapshot the harness overwrites")
  end

  it "says nothing of a snapshot when the plan is inside the repository root" do
    text = described_class.new(agent:, subject: plan, root: File.dirname(plans_root), profile:).to_s
    expect(text).not_to include("snapshot the harness overwrites")
  end

  it "opens with the agent's own definition" do
    expect(text).to start_with(agent.prompt)
  end

  it "states the budgets the executor will enforce" do
    expect(text).to include("Token budget — 1000 tokens", "Time budget - 120 seconds")
  end

  it "names the round and the successor in the signing command" do
    expect(text).to include("--round 3 --status Completed --next hansolo-reviewer")
  end

  # The agent's PATH can hold an older release that has no `state sign`.
  it "signs through this checkout's own executable, not whatever is on PATH" do
    expect(text).to include("#{described_class::EXECUTABLE} state sign --dir")
  end

  it "lists what is withheld and what is granted" do
    expect(text).to include("  git push", "You may run these, which most agents may not:\n\n  gh pr review")
  end

  context "when the spec suggests an implementation" do
    let(:spec_body) { "---\nimplementation_suggestions:\n  - Ruby with dry-cli\n---\n# A Feature\n" }

    it "shows the suggestions, labelled as advice" do
      expect(text).to include("Implementation suggestions", "suggestions, not requirements", "- Ruby with dry-cli")
    end
  end

  context "when the spec requires an implementation" do
    let(:spec_body) { "---\nimplementation_requirements:\n  - The database is PG-strict\n---\n# A Feature\n" }

    it "states them as binding, with the way out" do
      expect(text).to include("Implementation requirements",
        "requirements, not suggestions",
        "- The database is PG-strict",
        "sign Blocked")
    end

    it "leaves out the suggestions section" do
      expect(text).not_to include("Implementation suggestions")
    end
  end

  context "when the spec says how the task is finished" do
    let(:spec_body) { "---\ntask-completed-when: the editor opens\nhow-to-verify: bundle exec rspec\n---\n# A Feature\n" }

    it "gives the builder and the reviewer the same two lists" do
      expect(text).to include("Completion criteria",
        "- the editor opens",
        "- bundle exec rspec",
        "## Task completed when",
        "## How to test")
    end
  end

  it "adds no completion section when the spec has none" do
    expect(text).not_to include("Completion criteria")
  end

  # r2d2-mechanic builds, so it carries the standing requirement even when
  # the spec states none; /repo names no justfile or Gemfile.
  it "requires the project's tests and linters to pass, though the spec says nothing" do
    expect(text).to include("Implementation requirements", "every test suite and linter the project defines passes")
  end

  context "when the agent writes documents, not code" do
    let(:agent) { OpenLanes::Agents.find("leah-researcher") }
    let(:plan) do
      plans { |t| t.plan "001.00", :new, "task", files: { "spec.md" => spec_body } }
      OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first
    end

    it "adds no requirements section when the spec has none" do
      expect(text).not_to include("Implementation requirements")
    end
  end

  it "adds no suggestions section when the spec has none" do
    expect(text).not_to include("Implementation suggestions")
  end

  it "adds no operator section when nobody steered the run" do
    expect(text).not_to include("Operator instructions")
  end
end

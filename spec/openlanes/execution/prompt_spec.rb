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
      successor: "staff-reviewer",
      max_tokens: 1000,
      seconds: 120,
      denied: ["git push"],
      granted: ["gh pr review"]).to_s
  end

  let(:agent) { OpenLanes::Agents.find("chores-coder") }
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

  describe "a reviewer's rejection cap and struck findings (plan 015)" do
    let(:agent) { OpenLanes::Agents.find("staff-reviewer") }

    def prompt = described_class.new(agent:, subject: plan, root: "/repo", profile:, max_rejections: -> { 3 }).to_s

    it "gives staff-reviewer the configured cap" do
      expect(prompt).to include("`merge.max_rejections` is 3: sign `rejected N/3`", "No finding has been struck.")
    end

    def strike(id, review:, heading: nil)
      OpenLanes::Plans::PlanState.for(plan.feature.path)
                                 .rule!(kind: "appeal",
                                   pr: 4,
                                   round: 1,
                                   outcome: "struck",
                                   findings: { struck: [id], headings: heading ? { id => heading } : {} },
                                   winner: nil,
                                   reason: "r",
                                   trigger: "appeal",
                                   review:)
    end

    it "names a struck finding by the review that raised it and its heading" do
      strike("F2", review: 1, heading: "lib/a.rb:10 asks for an out-of-scope test")
      expect(prompt).to include("never to be raised again", "- F2 of review round 1: lib/a.rb:10 asks for an out-of-scope test")
    end

    # staff-reviewer numbers from F1 in every review: round 2's F2 is another finding.
    it "keeps the same id from two reviews apart" do
      strike("F2", review: 1)
      strike("F2", review: 2)
      expect(prompt).to include("- F2 of review round 1\n", "- F2 of review round 2\n")
    end

    it "hands every reviewer the shared brief, after its own definition" do
      expect(prompt).to include("#{agent.prompt}\n\n## How every reviewer works")
    end

    it "names the model the reviewer runs as, for its opening line" do
      expect(prompt).to include("You run as `#{profile}`")
    end

    context "when a project's agents carry a brief of their own" do
      let(:dir) { File.join(File.dirname(plans_root), "agents") }
      let(:agent) { OpenLanes::Agents::Registry.new(dir:).find("staff-reviewer") }

      before do
        FileUtils.mkdir_p(File.join(dir, "shared"))
        FileUtils.cp(OpenLanes::Agents.find("staff-reviewer").path, dir)
        File.write(File.join(dir, "shared", "review.md"), "## Our own brief\n")
      end

      it { expect(prompt).to include("## Our own brief") }
      it { expect(prompt).not_to include("## How every reviewer works") }
    end

    it "tells a builder nothing about the cap" do
      builder = OpenLanes::Agents.find("backend-coder")
      expect(described_class.new(agent: builder, subject: plan, root: "/repo", profile: OpenLanes::Agents::Profile.resolve(builder)).to_s)
        .not_to include("## Rejection cap", "## How every reviewer works")
    end
  end

  it "opens with the agent's own definition" do
    expect(text).to start_with(agent.prompt)
  end

  it "states the budgets the executor will enforce" do
    expect(text).to include("Token budget — 1000 tokens", "Time budget - 120 seconds")
  end

  it "names the round and the successor in the signing command" do
    expect(text).to include("--round 3 --status Completed --next staff-reviewer")
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

  # chores-coder builds, so it carries the standing requirement even when
  # the spec states none; /repo names no justfile or Gemfile.
  it "requires the project's tests and linters to pass, though the spec says nothing" do
    expect(text).to include("Implementation requirements", "every test suite and linter the project defines passes")
  end

  context "when the agent writes documents, not code" do
    let(:agent) { OpenLanes::Agents.find("researcher") }
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

  # A stopped rebase (D10): the invocation resolves it and nothing else.
  describe "a rebase to resolve" do
    let(:stopped) do
      OpenLanes::Vcs::Refresh::Outcome.new(kind: :conflicted, base: "origin/main", files: ["app.rb", "lib/x.rb"])
    end
    let(:resolution) do
      described_class.new(agent:,
        subject: plan,
        root: "/repo",
        profile:,
        control: "/tmp/control",
        denied: ["git push", "git rebase"],
        rebase: stopped).to_s
    end

    it "keeps the agent's own definition first, so its rebase section is read" do
      expect(resolution).to start_with(agent.prompt)
    end

    it "names the base and every conflicted file" do
      expect(resolution).to include("onto `origin/main`", "  app.rb\n  lib/x.rb")
    end

    it "says it is not plan work, and that a conflict never goes to a person" do
      expect(resolution).to include("This is not plan work", "never a question", "favour what")
    end

    it "asks for staging and forbids everything that moves HEAD" do
      expect(resolution).to include("`git add` each file", "Never run `git rebase`", "`git commit`", "  git rebase")
    end

    it "asks for each judgement call in plan.md" do
      expect(resolution).to include("## Rebase decisions")
    end

    it "carries no ledger section, so nothing reads it as the round's verdict" do
      expect(resolution).not_to include("state sign")
    end

    it "names the control file" do
      expect(resolution).to include("Your control file is /tmp/control")
    end
  end
end

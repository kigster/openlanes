# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OpenLanes::Agents::Registry do
  subject(:agents) { described_class.new(dir: @dir) }

  around do |example|
    Dir.mktmpdir("agents") do |tmp|
      @dir = tmp
      %w[researcher backend-coder unblocker staff-reviewer].each do |name|
        File.write(File.join(tmp, "#{name}.md"), <<~MD)
          ---
          name: #{name}
          description: #{name} does its one thing.
          handles: [building]
          ---
          Prompt for #{name}.
        MD
      end
      example.run
    end
  end

  def names(result) = result.map(&:name)

  # `run --agent` and `run --skip` narrow the roster the loop assigns from,
  # so the narrowing has to live here rather than in the command.
  describe "#only and #without" do
    it "keeps exactly the agents named" do
      expect(names(agents.only("backend-coder").all)).to eq(["backend-coder"])
    end

    it "drops exactly the agents named, preserving order" do
      expect(names(agents.without("backend-coder", "unblocker").all))
        .to eq(%w[researcher staff-reviewer])
    end

    it "derives a roster the original does not share state with" do
      agents.only("backend-coder")

      expect(names(agents.all).size).to eq(4)
    end
  end

  # `agents describe researcher` should not make anyone type the whole hyphenated
  # name, let alone the file name with its extension.
  describe "#match" do
    it "finds an agent by its exact name" do
      expect(names(agents.match("backend-coder"))).to eq(%w[backend-coder])
    end

    it "accepts the file name tab completion produces" do
      expect(names(agents.match("researcher.md"))).to eq(%w[researcher])
    end

    it "accepts a whole path, since completion in agents/ yields one" do
      expect(names(agents.match("agents/unblocker.md"))).to eq(%w[unblocker])
    end

    it "finds an agent by the first word of its name" do
      expect(names(agents.match("researcher"))).to eq(%w[researcher])
    end

    it "finds an agent by a fragment from the middle" do
      expect(names(agents.match("review"))).to eq(%w[staff-reviewer])
    end

    it "returns every candidate when the fragment fits several" do
      expect(names(agents.match("c"))).to contain_exactly("unblocker", "researcher", "backend-coder")
    end

    # An exact hit must never be widened: an agent named `backend-coder` alongside
    # `backend-coder` would otherwise make `backend-coder` permanently ambiguous.
    it "prefers an exact name over the prefixes it also fits" do
      File.write(File.join(@dir, "backend-coder.md"), <<~MD)
        ---
        name: backend-coder
        description: The short-named one.
        handles: [building]
        ---
        Prompt.
      MD

      expect(names(agents.match("backend-coder"))).to eq(%w[backend-coder])
    end

    it "returns nothing for a fragment no name contains" do
      expect(agents.match("ghost-agent")).to be_empty
    end
  end

  describe "an agent's own timeout" do
    it "reads a positive timeout from the frontmatter" do
      File.write(File.join(@dir, "slowpoke.md"), <<~MD)
        ---
        name: slowpoke
        description: Takes its time.
        handles: [building]
        timeout: 1800
        ---
        Prompt.
      MD

      expect(agents.find("slowpoke").timeout).to eq(1800)
    end

    it "leaves the timeout nil when the definition says nothing, deferring to the run" do
      expect(agents.find("backend-coder").timeout).to be_nil
    end

    # A zero or negative timeout would abandon the agent before it starts;
    # nothing an author writes should be able to mean that.
    it "treats a non-positive timeout as unset" do
      File.write(File.join(@dir, "hasty.md"), <<~MD)
        ---
        name: hasty
        description: Misconfigured.
        handles: [building]
        timeout: 0
        ---
        Prompt.
      MD

      expect(agents.find("hasty").timeout).to be_nil
    end
  end

  describe "the ledger, rounds, effort and the rename hooks" do
    let(:agents) { described_class.new }

    it "lists the documents each agent signs, in order" do
      aggregate_failures do
        expect(agents.find("researcher").ledger).to eq(%w[spec.md])
        expect(agents.find("backend-coder").ledger).to eq(%w[plan.md pull-requests.md plan-backend.md])
        expect(agents.find("frontend-coder").ledger).to eq(%w[plan.md pull-requests.md plan-frontend.md])
        expect(agents.find("staff-reviewer").ledger).to eq(%w[pull-requests.md])
        # Not plan.md: signing a spec-stage block into a new plan.md would
        # justify 📋 and skip research and specification.
        expect(agents.find("unblocker").ledger).to eq(%w[spec.md])
      end
    end

    it "defaults rounds to one and caps them at five" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.md"), "---\nname: a\nhandles: [new]\nrounds: 9\n---\nbody")
        File.write(File.join(dir, "b.md"), "---\nname: b\nhandles: [new]\n---\nbody")
        roster = described_class.new(dir:)
        expect(roster.find("a").rounds).to eq(OpenLanes::Agents::Agent::MAX_ROUNDS)
        expect(roster.find("b").rounds).to eq(1)
      end
    end

    it "reads the model and effort the definitions declare" do
      aggregate_failures do
        expect(agents.find("researcher").model).to eq("haiku")
        expect(agents.find("researcher").effort).to eq("medium")
        expect(agents.find("staff-reviewer").model).to eq("sonnet")
        expect(agents.find("unblocker").effort).to eq("low")
      end
    end

    # The ceiling is Opus. Anything costlier is clamped by the adapter, but a
    # definition that asks for it is still a definition that misleads.
    it "asks for no model above Opus" do
      expect(agents.all.map(&:model).uniq - %w[haiku sonnet opus]).to eq([])
    end

    it "reads the adapter, phase, lanes, needs and toggle" do
      frontend_coder = agents.find("frontend-coder")
      expect([frontend_coder.adapter, frontend_coder.phase, frontend_coder.starts, frontend_coder.needs, frontend_coder.toggle])
        .to eq([nil, "frontend", %i[research planning], ["plan.md#frontend"], "frontend"])
    end

    it("reads an adapter the definition names") { expect(agents.find("verifier").adapter).to eq("claude") }

    it "refuses an effort outside the scale" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "x.md"), "---\nname: x\neffort: ultra\n---\nbody\n")
        expect { described_class.new(dir:).all }.to raise_error(OpenLanes::Error, /effort "ultra"/)
      end
    end

    it "refuses an adapter nothing answers to" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "x.md"), "---\nname: x\nadapter: gpt\n---\nbody\n")
        expect { described_class.new(dir:).all }.to raise_error(OpenLanes::Error, /adapter "gpt"/)
      end
    end

    # The executor expands confined_to against the plan folder, so a path
    # that climbs out of it would grant Edit on a file outside.
    ["../Gemfile", "/etc/hosts", "~/x", "docs/../../x", ""].each do |file|
      it "refuses confined_to #{file.inspect}, which is not inside the plan folder" do
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, "x.md"), "---\nname: x\nconfined_to: [#{file.to_json}]\n---\nbody\n")
          expect { described_class.new(dir:).all }.to raise_error(OpenLanes::Error, /confined_to #{Regexp.escape(file.inspect)}/)
        end
      end
    end

    it "accepts confined_to naming a file inside the plan folder" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "x.md"), "---\nname: x\nconfined_to: [spec.md, notes/a.md]\n---\nbody\n")
        expect(described_class.new(dir:).find("x").confined_to).to eq(%w[spec.md notes/a.md])
      end
    end

    it "reads the timeouts as settled" do
      expect(agents.all.to_h { |a| [a.name, a.timeout] }).to include(
        "spec-writer"    => 900,
        "planner"        => 600,
        "backend-coder"  => 1200,
        "frontend-coder" => 1200,
        "staff-reviewer" => 300,
        "researcher"     => 300
      )
    end

    it "knows the state backend-coder starts a plan into and the one it holds at while frontend-coder is still building" do
      backend_coder = agents.find("backend-coder")
      expect([backend_coder.starts_as, backend_coder.holds_at]).to eq(%i[building building_ui])
      expect(agents.find("frontend-coder").starts_as).to be_nil
    end

    it "gives staff-reviewer in_review as the state a review starts in" do
      expect(agents.find("staff-reviewer").starts_as).to eq(:in_review)
    end

    it "strips the name to the role for the screen" do
      expect(agents.find("planner").role).to eq("planner")
    end
  end

  describe "the prompts" do
    let(:agents) { described_class.new }

    # A4: the harness renames. A prompt that still says `git mv` would race it.
    it "never tells an agent to rename its own folder" do
      agents.all.each do |agent|
        expect(agent.prompt).not_to include("git mv"), "#{agent.name} still renames its folder"
      end
    end

    it "tells backend-coder and frontend-coder to sign pull-requests.md" do
      %w[backend-coder frontend-coder].each do |name|
        expect(agents.find(name).prompt).to include("pull-requests.md")
      end
    end

    it "tells staff-reviewer the verdict words, the finding headings and the configured cap" do
      prompt = agents.find("staff-reviewer").prompt
      expect(prompt).to include("(rejected 1/2)", "(rejected 2/2)", "(rejected K+1/M)", "### F<n> [critical|minor]", "(great)", "(passed)", "(slop)", "👍🏼 to deploy")
    end

    it "lets staff-reviewer comment, but neither review nor edit a pull request" do
      aggregate_failures do
        expect(agents.find("staff-reviewer").may).to eq(["gh pr comment"])
        expect(OpenLanes::Execution::Executor::FORBIDDEN_COMMANDS).to include("gh pr edit")
      end
    end

    it "tells staff-reviewer the engine labels, not it" do
      expect(agents.find("staff-reviewer").prompt).to include("Never run `openlanes review` or `gh pr edit`")
    end

    it "gives verifier 🧪 Verifying, the verification phase, and nothing that leaves the machine" do
      verifier = agents.find("verifier")

      aggregate_failures do
        expect(verifier).to have_attributes(handles: [:verifying],
          advances_to: :approved,
          phase: "verification",
          adapter: "claude",
          may: [],
          ledger: %w[pull-requests.md])
        expect(verifier.allowed_tools).to match_array(%w[Read Grep Glob Bash Write])
        expect(agents.for_status(OpenLanes::Plans::STATUS_BY_KEY.fetch(:verifying)).map(&:name)).to eq(%w[verifier])
      end
    end

    it "tells verifier both verdict words, the report it writes, and where its screenshots go" do
      expect(agents.find("verifier").prompt)
        .to include("(verified)", "(rejected)", "## Failing step", "step-NN.png", "final.png", "report.md", "app.md")
    end

    it "tells staff-reviewer an approval goes on to verifier" do
      expect(agents.find("staff-reviewer").prompt).to include("🧪 Verifying", "verifier")
    end

    it "tells spec-writer to leave a blank plan.md" do
      expect(agents.find("spec-writer").prompt).to include("plan.md")
    end
  end

  # The prompts promise moves; the machine decides whether they happen. Each
  # example here is one way the two used to disagree.
  describe "the real roster against the state machine" do
    let(:agents) { described_class.new }

    def status(key) = OpenLanes::Plans::STATUS_BY_KEY.fetch(key)

    it "lets every agent told how to block, block from every state it handles" do
      aggregate_failures do
        agents.all.select { |a| a.prompt.include?("Blocked, round N") }.each do |agent|
          agent.handles.each do |key|
            %i[blocked product_blocked].each do |to|
              expect(OpenLanes::Plans::StateMachine.edge?(key, to)).to be(true), "#{agent.name} may sign Blocked at #{key}, but #{key} cannot become #{to}"
            end
          end
        end
      end
    end

    it "leaves no state an agent holds a plan at without an agent to resume it" do
      agents.all.filter_map(&:holds_at).each do |key|
        expect(agents.for_status(status(key))).not_to be_empty, "nobody resumes a plan held at #{key}"
      end
    end

    # The loop never offers work in a settled state, so a destination
    # declared there is a promise nothing keeps.
    it "declares no destination for an agent only a command can start" do
      agents.all.select { |a| a.handles.all? { |k| OpenLanes::Plans::StateMachine::SETTLED.include?(k) } }.each do |agent|
        expect(agent.advances_to).to be_nil, "#{agent.name} declares advances_to, but run never starts it"
      end
    end

    it "counts the partner who finished and holds the plan as part of its team" do
      expect(names(agents.team_for(status(:building_ui)))).to contain_exactly("backend-coder", "frontend-coder")
      expect(names(agents.team_for(status(:building)))).to contain_exactly("backend-coder", "chores-coder", "frontend-coder")
      expect(names(agents.team_for(status(:new)))).to eq(%w[researcher])
    end
  end

  # Invoked only by the harness for a stopped rebase (D10), never routed to
  # a plan state, so `handles` is empty, as copilot's is.
  describe "rebaser, as the repository defines it" do
    let(:shipped) { described_class.new }
    let(:rebaser) { shipped.find("rebaser") }

    it "handles no plan state and is never offered one" do
      offered = OpenLanes::Plans::STATUSES.flat_map { |status| shipped.for_status(status).map(&:name) }

      aggregate_failures do
        expect(rebaser).to have_attributes(handles: [], phase: "rebase", model: "sonnet", effort: "high")
        expect(offered).not_to include("rebaser")
      end
    end

    it "is withheld git rebase and git commit like every agent, and granted nothing" do
      expect(rebaser.may).to eq([])
    end
  end

  # M7: the arbitrator reads and answers; the engine records and acts.
  describe "arbitrator, as the repository defines it" do
    let(:shipped) { described_class.new }
    let(:obi) { shipped.find("arbitrator") }

    it "is reached by the builders' appeals and disputes" do
      expect(%w[backend-coder frontend-coder].map { shipped.find(it).prompt })
        .to all(include("--note \"appeal: F<n> because <reason>\"", "--to arbitrator", "dispute:"))
    end

    it "is read-only and is never offered a plan state" do
      offered = OpenLanes::Plans::STATUSES.flat_map { |status| shipped.for_status(status).map(&:name) }

      aggregate_failures do
        expect(obi).to have_attributes(handles: [], advances_to: nil, phase: "arbitration", model: "opus", may: [])
        expect(obi.allowed_tools).to eq(["Read", "Grep", "Glob", "Bash(gh pr view:*)", "Bash(gh pr diff:*)",
                                         "Bash(openlanes state show:*)", "Bash(openlanes mail read:*)"])
        expect(offered).not_to include("arbitrator")
      end
    end
  end
end

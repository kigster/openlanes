# frozen_string_literal: true

# The push is the only part that talks to Linear, so it is the only part that
# needs a fake. The transport is injected at the GraphQL boundary rather than
# stubbed on the API object, so the queries themselves are exercised: a
# mutation whose variables are wrong still fails here.
RSpec.describe OpenLanes::Linear::Push, :tree do
  subject(:push) { described_class.new(import:, api:, tree:) }

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:project) { { "id" => "p-1", "name" => "US Tax Law: Self Contained Ruby Gem", "url" => "https://linear.app/p-1" } }
  let(:api) { OpenLanes::Linear::API.new(transport: fake) }
  let(:calls) { [] }
  let(:issued) { [] }

  let(:import) { fresh_import }
  let(:states) do
    [{ "id" => "s-backlog", "name" => "Backlog", "type" => "backlog", "position" => 0 },
     { "id" => "s-todo", "name" => "Todo", "type" => "unstarted", "position" => 1 },
     { "id" => "s-doing", "name" => "Doing", "type" => "started", "position" => 2 },
     { "id" => "s-done", "name" => "Done", "type" => "completed", "position" => 3 }]
  end
  let(:labels) { [{ "id" => "l-blocked", "name" => "blocked" }] }
  # Answers whichever operation it is handed, and records what it was asked.
  let(:fake) do
    lambda { |document, variables|
      calls << [document[/mutation (\w+)|query (\w+)/, 1], variables]
      { "data" => response_for(document, variables) }
    }
  end
  let!(:built) do
    plans do |t|
      t.plan "002.00",
        :approved,
        "dev-foundation",
        files: { "spec.md" => spec_body(title: "Dev Foundation"),
                 "plan.md" => "## PR-1 — Test rig\n\nThe rig.\n" },
        prs:   [t.merged(2, "Spec 002 PR-1: Test rig")]
    end
  end

  def fresh_import
    OpenLanes::Linear::Import.new(tree: OpenLanes::Plans::Tree.new(dir: plans_root), team: "TAX", project:)
  end

  def response_for(document, variables)
    case document
    when /teams\(filter/
      { "teams" => { "nodes" => [{ "id" => "team-1", "name" => "Tax", "key" => "TAX",
                                "states" => { "nodes" => states }, "labels" => { "nodes" => labels } }] } }
    when /issueCreate/
      issued << variables[:input]
      number = 40 + issued.size
      { "issueCreate" => { "success" => true, "issue" => { "id"         => "i-#{number}",
                                                           "identifier" => "TAX-#{number}",
                                                           "url"        => "https://linear.app/TAX-#{number}" } } }
    when /issueUpdate/
      { "issueUpdate" => { "success" => true, "issue" => { "id" => "i-40", "identifier" => variables[:id],
                                                        "url" => "https://linear.app/#{variables[:id]}" } } }
    when /issueLabelCreate/
      { "issueLabelCreate" => { "success" => true, "issueLabel" => { "id" => "l-new", "name" => variables[:input][:name] } } }
    when /attachmentCreate/ then { "attachmentCreate" => { "success" => true, "attachment" => { "id" => "a-1" } } }
    end
  end

  describe "#call" do
    it "never creates a project, whatever the plans look like" do
      push.call

      expect(calls.map(&:first)).not_to include("CreateProject", "UpdateProject")
    end

    it "files every issue under the project it was given" do
      push.call

      expect(issued.map { |i| i[:projectId] }.uniq).to eq(["p-1"])
    end

    # A child names its parent by the identifier Linear just handed back,
    # which is why the folder's own issue is pushed first and alone.
    it "creates the plan's own issue before the children that name it" do
      push.call

      expect(issued.map { |i| i[:parentId] }).to eq([nil, "TAX-41"])
    end

    it "attaches the pull request to the issue it created" do
      push.call
      _, variables = calls.find { |name, _| name == "CreateAttachment" }

      expect(variables[:input][:url]).to eq("https://github.com/example/repo/pull/2")
    end
  end

  describe "resolving a workflow state" do
    # A team that calls its started state "Doing" is not a broken team, and an
    # import that only knows the word "In Progress" would file every plan
    # wrong on it.
    it "falls back to the type when the team has no state by that name" do
      plans { |t| t.plan "005.00", :building, "in-flight", files: { "spec.md" => spec_body }, prs: [t.open(9, "WIP")] }
      push.call

      expect(issued.map { |i| i[:stateId] }).to include("s-doing")
    end

    it "prefers the team's own name for a state when it has one" do
      push.call

      expect(issued.first[:stateId]).to eq("s-done")
    end
  end

  describe "labels" do
    it "reuses a label the team already has rather than making a second one" do
      plans { |t| t.plan "006.00", :blocked, "stuck", files: { "blocked.md" => "B1. Which tier?" } }
      push.call

      aggregate_failures do
        expect(calls.map(&:first)).not_to include("CreateLabel")
        expect(issued.map { |i| i[:labelIds] }).to include(["l-blocked"])
      end
    end

    it "creates one the team is missing" do
      plans { |t| t.plan "007.00", :deployed, "shipped", files: { "deployed.md" => "v1.2.0" } }
      push.call

      expect(calls.filter_map { |n, v| v[:input][:name] if n == "CreateLabel" }).to eq(["deployed"])
    end
  end

  describe "what it records" do
    let(:record) { OpenLanes::Linear::Issues.new(dir: File.join(plans_root, "002.00-✅ → dev-foundation")) }

    before { push.call }

    it "names both the plan's issue and its child" do
      expect(record.all.map { |i| [i.unit, i.identifier] }).to eq([["PLAN", "TAX-41"], ["PR-1", "TAX-42"]])
    end

    it "records the project, so a later run knows where this was filed" do
      expect(record.project).to include(name: "US Tax Law: Self Contained Ruby Gem")
    end

    # The whole point of the fingerprint: an unchanged plan costs nothing.
    it "leaves a record a second import reads as nothing to do" do
      expect(fresh_import.pending).to be_empty
    end
  end

  # The steady state. Everything above is the first run; this is every run
  # after it, and the failure it guards against — a duplicate of the lot — is
  # the one that would be worst to discover by looking at Linear.
  describe "running a second time over a tree it has already imported" do
    before { push.call }

    it "creates nothing at all" do
      calls.clear
      described_class.new(import: fresh_import, api:, tree:).call

      expect(calls.map(&:first)).not_to include("CreateIssue")
    end

    it "updates rather than duplicates once the plan changes underneath it" do
      File.write(File.join(plans_root, "002.00-✅ → dev-foundation", "plan.md"),
        "## PR-1 — Test rig, rewritten\n\nDifferent now.\n")
      calls.clear
      described_class.new(import: fresh_import, api:, tree:).call

      aggregate_failures do
        expect(calls.map(&:first)).to include("UpdateIssue")
        expect(calls.map(&:first)).not_to include("CreateIssue")
      end
    end
  end

  describe "when Linear refuses something" do
    let(:fake) do
      lambda { |document, variables|
        calls << [document[/mutation (\w+)|query (\w+)/, 1], variables]
        next { "errors" => [{ "message" => "title is too long" }] } if document.match?(/issueCreate/)

        { "data" => response_for(document, variables) }
      }
    end

    it "reports the failure against the action that caused it" do
      expect(push.call.reject(&:ok?).map(&:error)).to include(a_string_including("title is too long"))
    end

    # A child cannot exist without its parent, so it is not attempted.
    it "does not try to hang a child off a parent that was never created" do
      errors = push.call.reject(&:ok?).map(&:error)

      expect(errors).to include(a_string_including("the issue for its plan could not be created"))
    end

    it "keeps going, so one bad plan does not strand the rest" do
      plans { |t| t.plan "008.00", :new, "next-one", files: { "spec.md" => spec_body } }

      expect(push.call.map { |r| r.action.ordinal }.uniq).to include("002.00", "008.00")
    end

    it "writes no linear.md claiming an issue that was never made" do
      push.call

      expect(File.exist?(File.join(plans_root, "002.00-✅ → dev-foundation", "linear.md"))).to be(false)
    end
  end
end

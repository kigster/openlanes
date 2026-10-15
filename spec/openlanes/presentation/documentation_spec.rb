# frozen_string_literal: true

# The document exists so that nobody hand-maintains a second copy of the status
# table. These examples are what stop the generator itself from becoming that
# second copy: every state, every edge and every rule has to appear, so adding
# a state to the machine without the document following is a failing build.
RSpec.describe OpenLanes::Presentation::Documentation do
  subject(:documentation) { described_class.new }

  let(:document) { documentation.render }

  describe "#render" do
    it "says plainly that it is generated, and how to regenerate it" do
      aggregate_failures do
        expect(document).to include("This file is auto generated")
        expect(document).to include("openlanes docs")
      end
    end

    it "spells every folder-name example the current way, with no arrow" do
      examples = document.scan(%r{^#{Regexp.escape(OpenLanes::PLANS_DIR)}/\S+.*$})

      aggregate_failures do
        expect(examples).not_to be_empty
        expect(examples.join("\n")).not_to include("→")
        expect(examples).to all(include("━━❯"))
      end
    end

    it "names each inactive subfolder and the lock file" do
      expect(document).to include("`.plans/archive/`", "`.plans/deferred/`", "`.plans/abandoned/`", "locked-by.pid")
    end

    it "documents every state the machine knows — emoji, label and key" do
      aggregate_failures do
        OpenLanes::Plans::STATUSES.each do |status|
          expect(document).to include(status.emoji), "#{status.key}: emoji missing"
          expect(document).to include(status.label), "#{status.key}: label missing"
          expect(document).to include("`#{status.key}`"), "#{status.key}: key missing"
          expect(document).to include(status.note), "#{status.key}: description missing"
        end
      end
    end

    it "documents every file a state requires" do
      required = OpenLanes::Plans::STATUSES.flat_map(&:requires).uniq

      aggregate_failures do
        required.each { |file| expect(document).to include("`#{file}`") }
      end
    end

    # Plan 003 folded the units into plan.md and renamed the contract.
    it "names contract.md and neither of the files it replaced" do
      aggregate_failures do
        expect(document).to include("`contract.md`", "`openapi.yaml`", "`## Frontend`")
        expect(document).not_to include("implementation-plan.md")
        expect(document).not_to include("plan-backend.md")
      end
    end

    it "renders every transition into the mermaid diagram" do
      diagram = document[/```mermaid\n(.*?)```/m, 1]

      aggregate_failures do
        expect(diagram).to include("stateDiagram-v2")
        OpenLanes::Plans::StateMachine.inbound.each do |to, froms|
          froms.each { |from| expect(diagram).to include("#{from} --> #{to}") }
        end
      end
    end

    it "names 🟣 Merged as deliberately not a folder state" do
      expect(document).to include("🟣 Merged is deliberately **not** a folder state")
    end

    it "explains the numbering, including that the decimal means sibling not part" do
      aggregate_failures do
        expect(document).to include("000.00")
        expect(document).to include("sibling of 001 that arrived later, not a part of 001")
        expect(document).to include("Two digits, always")
      end
    end

    it "records what padding every plan to NNN.MM costs, rather than only what it buys" do
      expect(document).to match(/costs something/i)
    end

    it "documents the no-plan prefix and that the tool never asserts it alone" do
      aggregate_failures do
        expect(document).to include("[#{OpenLanes::NO_PLAN_PREFIX}]")
        expect(document).to include("assumed")
        expect(document).to match(/refuses rather than guessing/i)
      end
    end

    it "keeps the exit clause for the day a real issue tracker arrives" do
      expect(document).to include("issue key replaces it")
    end

    it "stamps the version it was generated from" do
      expect(document).to include(OpenLanes::VERSION)
    end

    it "documents create's four-heading brief, verbatim and in order" do
      section = document[/^## Starting a feature.*?\n(.*?)^## /m, 1].to_s
      headings = section.scan(/^- `## (.+)`$/).flatten

      expect(headings).to eq(OpenLanes::Lifecycle::Brief::HEADINGS)
    end

    it "says plainly that create writes no Goals, no Non-Goals and no Research heading" do
      aggregate_failures do
        expect(document).to match(/writes no `## Goals`, no\n`## Non-Goals`/)
        expect(document).to include('writes no heading beginning with the word "Research"')
      end
    end

    it "distinguishes the brief from the retroactive --prs path" do
      expect(document).to include("`create --after <plan> --prs")
    end
  end

  describe "drift" do
    # The failure this catches: someone adds a state to STATUSES, the tables
    # pick it up automatically, but the prose still describes the old set.
    it "mentions as many states in the table as the machine defines" do
      table = document[/^## The states\n(.*?)^## /m, 1].to_s
      rows = table.lines.count { |l| l.start_with?("| ") && !l.match?(/:----|Symbol/) }

      expect(rows).to eq(OpenLanes::Plans::STATUSES.size)
    end

    it "lists a spine destination for exactly the states that have one" do
      table = document[/^## Transitions\n(.*?)^A bare promote/m, 1].to_s
      dashes = table.lines.count { |l| l.end_with?("| — |\n") }

      expect(dashes).to eq(OpenLanes::Plans::STATUSES.size - OpenLanes::Plans::StateMachine::SPINE.size)
    end
  end
end

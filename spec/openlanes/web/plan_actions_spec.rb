# frozen_string_literal: true

# The "Plan Management" menu's actions, against a real .plans tree.
RSpec.describe OpenLanes::Web::PlanActions, :tree do
  let(:busy) { [] }
  let(:service) { described_class.new(plans_dir: plans_root, working: ->(o) { busy.include?(o) }) }
  let(:spec_body) { "---\ndepends_on: [\"001.00\"] # waits on the base\n---\n\n# Tax rules\n\nA DSL for tax rules.\n" }

  before do
    plans do |t|
      t.plan("001.00", :new, "base", files: { "spec.md" => "# Base\n\nThe base.\n" })
      t.plan("003.00", :planned, "tax-rules", files: { "spec.md" => spec_body, "plan.md" => "# Plan\n" })
      t.plan("004.00", :building, "web-room", files: { "spec.md" => "# Web\n\nThe room.\n", "plan.md" => "# Plan\n" })
    end
  end

  def folder(ordinal) = Dir.children(plans_root).find { it.start_with?(ordinal) }

  describe "#offer" do
    it "offers a plan not yet built every action, and says it has not started" do
      expect(service.offer("003").to_h).to eq(ordinal: "003.00",
        status: "planned",
        started: false,
        running: false,
        depends_on: ["001.00"],
        actions: %w[clear_dependencies discard defer])
    end

    it "counts a plan being built as started, and offers no dependencies to clear when it has none" do
      expect(service.offer("004.00").to_h).to include(started: true, depends_on: [], actions: %w[discard defer])
    end

    it "counts a plan an agent is on as started and running" do
      busy << "001.00"
      expect(service.offer("001.00").to_h).to include(started: true, running: true)
    end

    it "refuses a plan that is not there" do
      expect { service.offer("009.00") }.to raise_error(described_class::NotFound, "there is no plan 009.00")
    end
  end

  describe "#call" do
    it "clears depends_on and keeps the rest of the frontmatter as written" do
      expect(service.call("003.00", "clear_dependencies").depends_on).to eq([])
      expect(File.read(File.join(plans_root, folder("003.00"), "spec.md"))).to start_with("---\ndepends_on: [none] # waits on the base\n")
    end

    it "discards a plan with its reason, into ❌" do
      expect(service.call("003.00", "discard", reason: "Superseded by 004").status).to eq("discarded")
      reason = Dir.glob(File.join(plans_root, "discarded", "003.00*", "discarded-reason.md")).first
      expect(File.read(reason)).to include("Superseded by 004")
    end

    it "defers a plan, naming what brings it back" do
      expect(service.call("004.00", "defer", reason: "the API is stable").status).to eq("deferred")
      expect(File.read(File.join(plans_root, folder("004.00"), "delayed.md"))).to include("Revisit when the API is stable")
    end

    it "keeps a reason that already names its trigger as typed" do
      service.call("004.00", "defer", reason: "Until Q3")
      expect(File.read(File.join(plans_root, folder("004.00"), "delayed.md"))).to include("\nUntil Q3\n")
    end

    it "refuses to discard or defer without a reason, and moves nothing" do
      expect { service.call("003.00", "discard") }.to raise_error(described_class::Refused, "say why it is discarded")
      expect { service.call("003.00", "defer", reason: " ") }.to raise_error(described_class::Refused, "say what should bring it back")
      expect(folder("003.00")).to include("⭐")
      expect(File).not_to exist(File.join(plans_root, folder("003.00"), "delayed.md"))
    end

    it "refuses a plan an agent is working on" do
      busy << "004.00"
      expect { service.call("004.00", "defer", reason: "later") }.to raise_error(described_class::Busy, /stop it first/)
    end

    it "refuses an action it does not know, or one not open to the plan" do
      expect { service.call("003.00", "explode") }.to raise_error(described_class::Refused, /not one of/)
      expect { service.call("004.00", "clear_dependencies") }.to raise_error(described_class::Refused, /cannot clear dependencies/)
    end
  end
end

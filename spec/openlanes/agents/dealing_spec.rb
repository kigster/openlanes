# frozen_string_literal: true

# Plan 031, V7 and D12: the reviewers dealt across the project's coding agents.
RSpec.describe OpenLanes::Agents::Dealing do
  subject(:dealing) { described_class.new(adapters:, fallback: "pi", usable:) }

  let(:adapters) { %w[claude codex gemini] }
  let(:usable) { described_class::ANY }

  def reviewer(name, phase: "review") = instance_double(OpenLanes::Agents::Agent, name:, phase:)
  def dealt(*names) = names.map { dealing.adapter_for(reviewer(it)) }

  it "deals staff, security and design to the first, second and third" do
    expect(dealt("staff-reviewer", "security-reviewer", "design-reviewer")).to eq(%w[claude codex gemini])
  end

  it "gives an agent that does not review the project's adapter" do
    expect(dealing.adapter_for(reviewer("backend-coder", phase: "build"))).to eq("pi")
  end

  it "reads both from .openlanes.yml" do
    allow(OpenLanes::Config).to receive(:current).and_return(OpenLanes::Config.new(adapter: "grok", review_adapters: %w[codex]))
    expect([described_class.current.adapter_for(reviewer("staff-reviewer")), described_class.current.adapter_for(reviewer("planner", phase: "planning"))])
      .to eq(%w[codex grok])
  end

  it "seats a reviewer it does not know after the last" do
    expect(dealt("style-reviewer")).to eq(%w[claude])
  end

  context "with fewer coding agents than reviewers" do
    let(:adapters) { %w[claude codex] }

    it("wraps") { expect(dealt("staff-reviewer", "security-reviewer", "design-reviewer")).to eq(%w[claude codex claude]) }
  end

  context "when the probe found one unusable" do
    let(:usable) { ->(name) { name != "codex" } }

    it("skips it before dealing") { expect(dealt("staff-reviewer", "security-reviewer", "design-reviewer")).to eq(%w[claude gemini claude]) }
  end

  context "when none is listed, or none is usable" do
    let(:adapters) { [] }

    it("falls back to the project's adapter") { expect(dealt("staff-reviewer")).to eq(%w[pi]) }
  end

  # Plan 031, D14: a failed reviewer runs again on the main coding agent.
  describe "#replacement_for" do
    subject(:dealing) { described_class.new(adapters:, fallback:, replacing: %w[security-reviewer]) }

    let(:fallback) { "pi" }

    it("gives a replaced reviewer the project's adapter") { expect(dealing.replacement_for(reviewer("security-reviewer"))).to eq("pi") }
    it("leaves the others alone") { expect(dealing.replacement_for(reviewer("staff-reviewer"))).to be_nil }

    context "when the project names no adapter" do
      let(:fallback) { nil }

      it("gives it claude") { expect(dealing.replacement_for(reviewer("security-reviewer"))).to eq("claude") }
    end
  end
end

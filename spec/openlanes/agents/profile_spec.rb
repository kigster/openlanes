# frozen_string_literal: true

RSpec.describe OpenLanes::Agents::Profile do
  let(:agent) do
    OpenLanes::Agents::Agent.new(name: "backend-coder",
      description: "",
      handles: [:planned],
      advances_to: :ready_for_review,
      model: "fable",
      allowed_tools: [],
      may: [],
      network: false,
      timeout: nil,
      prompt: "",
      path: "",
      effort: "high",
      phase: "build")
  end

  def spec(frontmatter) = OpenLanes::Plans::Spec.parse("---\n#{frontmatter}\n---\n")

  it "takes the agent's own settings, with the model capped at Opus" do
    expect(described_class.resolve(agent).to_s).to eq("claude:opus/high")
  end

  it "lets the plan's depth set the effort" do
    expect(described_class.resolve(agent, spec: spec("depth: fast")).effort).to eq("low")
  end

  it "lets a phase override beat the depth" do
    expect(described_class.resolve(agent, spec: spec("depth: fast\nphases:\n  build: { effort: max }")).effort).to eq("max")
  end

  it "switches adapter and drops the agent's Claude model" do
    expect(described_class.resolve(agent, spec: spec("phases:\n  build: { adapter: codex }")).to_s).to eq("codex:default/high")
  end

  it "lets run --model beat everything" do
    expect(described_class.resolve(agent, spec: spec("phases:\n  build: { model: haiku }"), model: "sonnet").model).to eq("sonnet")
  end

  it "ignores overrides for other phases" do
    expect(described_class.resolve(agent, spec: spec("phases:\n  review: { model: haiku }")).model).to eq("opus")
  end

  # Plan 031, D12: below the agent's and the plan's word, above the project's.
  describe "a reviewer dealt a coding agent" do
    subject(:profile) { described_class.resolve(agent, spec: plan, dealing:) }

    let(:agent) { super().with(name: "security-reviewer", phase: "review") }
    let(:dealing) { OpenLanes::Agents::Dealing.new(adapters: %w[claude codex], fallback: "pi") }
    let(:plan) { nil }

    it("runs on its seat, ahead of the project's adapter") { expect(profile.adapter.name).to eq("codex") }

    context "when the agent names its own" do
      let(:agent) { super().with(adapter: "claude") }

      it("keeps the agent's") { expect(profile.adapter.name).to eq("claude") }
    end

    context "when the plan names one for the review phase" do
      let(:plan) { spec("phases:\n  review: { adapter: gemini }") }

      it("keeps the plan's") { expect(profile.adapter.name).to eq("gemini") }
    end

    context "when the project lists none" do
      let(:dealing) { OpenLanes::Agents::Dealing.new(adapters: [], fallback: "pi") }

      it("falls back to the project's adapter") { expect(profile.adapter.name).to eq("pi") }
    end
  end

  # Plan 040, D2: frontmatter, then `.openlanes.yml`, then claude.
  describe "the project's default adapter" do
    subject(:profile) { described_class.resolve(agent, spec: plan, dealing: OpenLanes::Agents::Dealing.new(fallback: "codex")) }

    let(:plan) { nil }

    it("runs an agent that names none on it, without its Claude model") { expect(profile.to_s).to eq("codex:default/high") }

    context "with an agent that names its own" do
      let(:agent) { super().with(adapter: "claude") }

      it("keeps the agent's") { expect(profile.to_s).to eq("claude:opus/high") }
    end

    context "with a plan that names one for the phase" do
      let(:plan) { spec("phases:\n  build: { adapter: pi }") }

      it("takes the plan's") { expect(profile.adapter.name).to eq("pi") }
    end

    context "when the project names claude" do
      subject(:profile) { described_class.resolve(agent, dealing: OpenLanes::Agents::Dealing.new(fallback: "claude")) }

      it("keeps the agent's Claude model") { expect(profile.model).to eq("opus") }
    end
  end

  it "reads the project's default from .openlanes.yml" do
    allow(OpenLanes::Config).to receive(:current).and_return(OpenLanes::Config.new(adapter: "codex"))
    expect(described_class.resolve(agent).adapter.name).to eq("codex")
  end

  describe "#label" do
    it "is the bare model for claude" do
      expect(described_class.resolve(agent).label).to eq("opus")
    end

    it "names any other adapter" do
      expect(described_class.resolve(agent, spec: spec("phases:\n  build: { adapter: pi, model: x }")).label).to eq("pi:x")
    end
  end
end

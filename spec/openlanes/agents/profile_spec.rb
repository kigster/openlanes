# frozen_string_literal: true

RSpec.describe OpenLanes::Agents::Profile do
  let(:agent) do
    OpenLanes::Agents::Agent.new(name: "luke-backend",
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

  describe "#label" do
    it "is the bare model for claude" do
      expect(described_class.resolve(agent).label).to eq("opus")
    end

    it "names any other adapter" do
      expect(described_class.resolve(agent, spec: spec("phases:\n  build: { adapter: pi, model: x }")).label).to eq("pi:x")
    end
  end
end

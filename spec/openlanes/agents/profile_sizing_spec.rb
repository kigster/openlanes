# frozen_string_literal: true

RSpec.describe OpenLanes::Agents::Profile do
  describe ".resolve, by unit size" do
    let(:fields) do
      { name: "backend-coder", description: "", handles: [:planned], advances_to: :ready_for_review, model: "opus",
        allowed_tools: [], may: [], network: false, timeout: nil, prompt: "", path: "", effort: "high", phase: "build" }
    end

    def agent(**changes) = OpenLanes::Agents::Agent.new(**fields, **changes)

    def spec(size, frontmatter = "starts: planning")
      OpenLanes::Plans::Spec.parse("---\n#{frontmatter}\n---\n").with(unit_size: size)
    end

    def configure(yaml = "jobs: 1\n")
      allow(OpenLanes::Config).to receive(:current).and_return(OpenLanes::Config.parse(yaml, path: ".openlanes.yml"))
    end

    before { configure }

    it "maps each size to its default profile" do
      profiles = %w[small medium large].map { described_class.resolve(agent, spec: spec(it)).to_s }
      expect(profiles).to eq(["claude:sonnet/medium", "claude:opus/medium", "claude:opus/high"])
    end

    it "maps a size to what sizing: configures" do
      configure("sizing:\n  small: { model: haiku, effort: low }\n")
      expect(described_class.resolve(agent, spec: spec("small")).to_s).to eq("claude:haiku/low")
    end

    it "keeps today's behaviour for a plan with no sized unit" do
      expect(described_class.resolve(agent(model: "haiku", effort: "low"), spec: spec(nil)).to_s).to eq("claude:haiku/low")
    end

    it "leaves agents that do not build alone" do
      expect(described_class.resolve(agent(phase: "review", model: "haiku", effort: "low"), spec: spec("large")).to_s)
        .to eq("claude:haiku/low")
    end

    it "lets run --model win over sizing" do
      expect(described_class.resolve(agent, spec: spec("small"), model: "haiku").model).to eq("haiku")
    end

    it "lets spec phases win over sizing" do
      profile = described_class.resolve(agent, spec: spec("small", "phases:\n  build: { model: haiku, effort: max }"))
      expect(profile.to_s).to eq("claude:haiku/max")
    end

    it "beats the spec's depth" do
      expect(described_class.resolve(agent, spec: spec("small", "depth: deep")).effort).to eq("medium")
    end

    it "outranks the agent's small_diff, which only stands in for the frontmatter" do
      small = OpenLanes::Agents::SmallDiff.new(under_lines: 50, model: "haiku", effort: "low")
      profile = described_class.resolve(agent(small_diff: small), spec: spec("large"), diff_lines: 10)

      expect(profile.to_s).to eq("claude:opus/high")
    end

    it "sets the effort alone for a builder on another coding agent, whose models the table does not name" do
      profile = described_class.resolve(agent(adapter: "codex", model: "gpt-5-codex"), spec: spec("large"))

      expect([profile.adapter.name, profile.model, profile.effort]).to eq(["codex", "gpt-5-codex", "high"])
    end

    it "reads the unit size from plan.md beside the spec" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "plan.md"), "### B1 X\n\n- **Size:** medium\n")
        plan = instance_double(OpenLanes::Plans::Subject, feature: Struct.new(:path).new(dir))
        allow(plan).to receive(:read).with("spec.md").and_return("---\nstarts: planning\n---\n")
        expect(OpenLanes::Plans::Spec.for(plan).unit_size).to eq("medium")
      end
    end
  end
end

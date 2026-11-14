# frozen_string_literal: true

RSpec.describe OpenLanes::Agents::Profile do
  describe ".resolve, by unit size" do
    let(:fields) do
      { name: "backend-coder", description: "", handles: [:planned], advances_to: :ready_for_review, model: "opus",
        allowed_tools: [], may: [], network: false, timeout: nil, prompt: "", path: "", effort: "high", phase: "build" }
    end
    let(:sizing) { OpenLanes::Agents::Sizing.new }

    def agent(**changes) = OpenLanes::Agents::Agent.new(**fields, **changes)

    def spec(frontmatter = "starts: planning") = OpenLanes::Plans::Spec.parse("---\n#{frontmatter}\n---\n")

    def sized(yaml) = OpenLanes::Config.parse(yaml, path: ".openlanes.yml").sizing

    def resolve(size, agent: agent(), spec: spec(), **rest)
      described_class.resolve(agent, spec:, unit_size: size, sizing:, **rest)
    end

    it "maps each size to its default profile" do
      expect(%w[small medium large].map { resolve(it).to_s }).to eq(["claude:sonnet/medium", "claude:opus/medium", "claude:opus/high"])
    end

    it "maps a size to what sizing: configures" do
      expect(resolve("small", sizing: sized("sizing:\n  small: { model: haiku, effort: low }\n")).to_s).to eq("claude:haiku/low")
    end

    it "keeps today's behaviour for a plan with no sized unit" do
      expect(resolve(nil, agent: agent(model: "haiku", effort: "low")).to_s).to eq("claude:haiku/low")
    end

    it "leaves agents that do not build alone" do
      expect(resolve("large", agent: agent(phase: "review", model: "haiku", effort: "low")).to_s).to eq("claude:haiku/low")
    end

    it "sizes the front-end builder too, from its phase" do
      expect(resolve("small", agent: agent(phase: "frontend")).to_s).to eq("claude:sonnet/medium")
    end

    it "lets run --model win over sizing" do
      expect(resolve("small", model: "haiku").model).to eq("haiku")
    end

    it "lets spec phases win over sizing" do
      expect(resolve("small", spec: spec("phases:\n  build: { model: haiku, effort: max }")).to_s).to eq("claude:haiku/max")
    end

    it "beats the spec's depth" do
      expect(resolve("small", spec: spec("depth: deep")).effort).to eq("medium")
    end

    it "reaches Fable when sizing.large.model names it" do
      expect(resolve("large", sizing: sized("sizing:\n  large: { model: fable }\n")).model).to eq("fable")
    end
  end

  describe OpenLanes::Plans::UnitSizes, ".in_folder" do
    it "reads the largest size from the folder's plan.md" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "plan.md"), "### B1 X\n\n- **Size:** medium\n")
        expect(described_class.in_folder(dir)).to eq("medium")
      end
    end

    it "answers nil for a folder with no plan.md" do
      Dir.mktmpdir { |dir| expect(described_class.in_folder(dir)).to be_nil }
    end
  end
end

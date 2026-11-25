# frozen_string_literal: true

# `by_quality:` frontmatter: a reviewer moves to a stronger model when the
# project's `.openlanes/config.yml` asks for `desired_codebase_quality: high`.
RSpec.describe OpenLanes::Agents::Profile do
  let(:reviewer) do
    OpenLanes::Agents::Agent.new(name: "staff-reviewer",
      description: "",
      handles: [:ready_for_review],
      advances_to: :approved,
      model: "opus",
      allowed_tools: [],
      may: [],
      network: false,
      timeout: nil,
      prompt: "",
      path: "staff-reviewer.md",
      effort: "high",
      phase: "review",
      small_diff: OpenLanes::Agents::SmallDiff.new(under_lines: 300, model: "sonnet", effort: "medium"),
      by_quality: OpenLanes::Agents::ByQuality.parse({ "high" => { "model" => "fable", "effort" => "high" } }, "staff-reviewer.md"))
  end

  def quality(value)
    yaml = value ? "desired_codebase_quality: #{value}\n" : "{}\n"
    allow(OpenLanes::Config).to receive(:current).and_return(OpenLanes::Config.parse(yaml, path: ".openlanes.yml"))
  end

  it "runs on the model named for high quality, even on a small diff" do
    quality("high")
    expect(described_class.resolve(reviewer, diff_lines: 10).to_s).to eq("claude:fable/high")
  end

  it "keeps the frontmatter's model for a quality it names nothing for, or none set" do
    aggregate_failures do
      quality("standard")
      expect(described_class.resolve(reviewer).model).to eq("opus")
      quality(nil)
      expect(described_class.resolve(reviewer).model).to eq("opus")
    end
  end

  it "gives back a key the operator set in .openlanes/config.yml agents:" do
    quality("high")
    overrides = OpenLanes::Agents::Overrides.new(table: { "staff-reviewer" => { model: "sonnet" } })
    expect(described_class.resolve(overrides.apply(reviewer), diff_lines: 1000).to_s).to eq("claude:sonnet/high")
  end

  it "holds on the agent's own CLI only" do
    quality("high")
    dealing = OpenLanes::Agents::Dealing.new(adapters: %w[codex], fallback: "pi")
    expect(described_class.resolve(reviewer.with(phase: "review"), dealing:).model).not_to eq("fable")
  end

  it "still yields to run --model and the plan's phases" do
    quality("high")
    plan = OpenLanes::Plans::Spec.parse("---\nphases:\n  review: { model: haiku }\n---\n")
    aggregate_failures do
      expect(described_class.resolve(reviewer, model: "sonnet").model).to eq("sonnet")
      expect(described_class.resolve(reviewer, spec: plan).model).to eq("haiku")
    end
  end
end

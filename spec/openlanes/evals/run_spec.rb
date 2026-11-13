# frozen_string_literal: true

RSpec.describe OpenLanes::Evals::Run, :tree do
  let(:path) { File.join(plans_root, "run.json") }

  it "reads seconds, tokens and the final state" do
    File.write(path, '{"seconds": 12, "tokens": "300", "state": "planned"}')

    expect(described_class.load(path)).to eq(described_class.new(seconds: 12.0, tokens: 300, state: :planned))
  end

  it "reads the final answer, which an arbitrator's ruling is scored by" do
    File.write(path, '{"answer": "```ruling\\nkind: cap\\n```"}')

    expect(described_class.load(path).answer).to eq("```ruling\nkind: cap\n```")
  end

  it "is empty when nothing was recorded" do
    expect(described_class.load(path)).to eq(described_class.new)
  end
end

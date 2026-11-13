# frozen_string_literal: true

RSpec.describe OpenLanes::Memory::Proposal do
  let(:fields) do
    { "slug" => "real-plan-trees", "title" => " Specs build real plan trees ", "applies_to" => ["build"], "kind" => "practice",
      "finding" => "spec stubbed\n  File.read", "body" => "Use PlansFixture." }
  end
  let(:line) { JSON.generate("lesson" => fields) }

  it "reads the lesson lines out of an answer, fenced or not, and skips the prose" do
    read = described_class.scan("I found one.\n`#{line}`\nThat is all: 1 lesson.\n")
    expect(read.map { [it.slug, it.title, it.applies_to, it.checked_by, it.kind, it.severity, it.finding] })
      .to eq([["real-plan-trees", "Specs build real plan trees", ["build"], [], "practice", nil, "spec stubbed File.read"]])
  end

  it "clips a body and a finding that run on" do
    long = described_class.read(JSON.generate("lesson" => fields.merge("body" => "x" * 5000, "finding" => "y" * 900)))
    expect([long.body.size, long.finding.size]).to eq([described_class::BODY_MAX, described_class::FINDING_MAX])
  end

  {
    "a lesson that is not an object" => ['{"lesson": 3}', "lesson is not an object"],
    "missing fields"                 => ['{"lesson": {"slug": "x", "title": " "}}', "title, finding, body missing"],
    "broken JSON"                    => ['{"lesson": {', /\Anot JSON: /]
  }.each do |what, (text, reason)|
    it "rejects #{what}, saying why" do
      expect(described_class.scan(text).map(&:reason)).to match([reason])
    end
  end
end

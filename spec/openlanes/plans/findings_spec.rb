# frozen_string_literal: true

RSpec.describe OpenLanes::Plans::Findings do
  let(:markdown) do
    <<~MARKDOWN
      # Pull Requests

      ## Findings: staff-reviewer

      ### F1 [critical] lib/tax/rule.rb:2

      A Float rate drifts.

      ### F2 [minor] spec/tax/rule_spec.rb:14

      One rate only.

      ## Verdict

      ### F9 not a finding
    MARKDOWN
  end

  let(:findings) { described_class.parse(markdown) }

  it "reads each finding under a reviewer's section, and nothing outside one" do
    expect(findings.map(&:wire)).to eq([
                                         { id: "F1", reviewer: "staff-reviewer", severity: "critical", file: "lib/tax/rule.rb", line: 2, text: "A Float rate drifts.", ruling: nil },
                                         { id: "F2", reviewer: "staff-reviewer", severity: "minor", file: "spec/tax/rule_spec.rb", line: 14, text: "One rate only.", ruling: nil }
                                       ])
  end

  it "reads an untagged finding as critical" do
    expect(described_class.parse("## Findings: x\n\n### F3 something broke\n").first.severity).to eq("critical")
  end

  describe "rulings" do
    def ruled(bucket, id, heading) = { "kind" => "finding", "findings" => { bucket => [id], "headings" => { id => heading } } }

    it "takes the latest ruling on a finding" do
      rulings = [ruled("struck", "F1", "[critical] lib/tax/rule.rb:2"), ruled("critical", "F1", "[critical] lib/tax/rule.rb:2")]
      expect(described_class.parse(markdown, rulings:).map(&:ruling)).to eq(["accept", nil])
    end

    it "ignores a ruling on an earlier review's finding of the same id" do
      rulings = [ruled("struck", "F1", "[minor] lib/other.rb:9")]
      expect(described_class.parse(markdown, rulings:).first.ruling).to be_nil
    end

    it "counts the arbitrator's strike, which names no heading" do
      rulings = [{ "kind" => "appeal", "findings" => { "struck" => ["F2"] } }]
      expect(described_class.parse(markdown, rulings:).map(&:ruling)).to eq([nil, "strike"])
    end
  end

  describe "a person's verdict" do
    let(:finding) { findings.first }

    it "builds the ruling the engine writes, so the demo board keeps the same shape" do
      expect(described_class.ruling_for(finding, "strike", by: "kig")).to eq(
        kind:     "finding",
        pr:       nil,
        round:    nil,
        outcome:  "struck",
        winner:   nil,
        trigger:  "person",
        reason:   "strike by kig",
        findings: { "struck" => ["F1"], "headings" => { "F1" => "[critical] lib/tax/rule.rb:2" } }
      )
    end

    it "writes it where the arbitrator's rulings go, and reads it back as the verdict", :tree do
      plans { |t| t.plan "001.00", :building, "work", files: { "pull-requests.md" => markdown } }
      path = OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first.feature.path
      written = described_class.rule!(path, described_class.for(path).last, "accept", by: "kig")
      aggregate_failures do
        expect(written).to include("kind" => "finding", "outcome" => "upheld", "trigger" => "person", "reason" => "accept by kig")
        expect(described_class.for(path).map(&:ruling)).to eq([nil, "accept"])
        expect(described_class.rules?(written, "F2")).to be(true)
        expect(described_class.rules?(written.merge("kind" => "cap"), "F2")).to be(false)
      end
    end

    it "refuses a verdict or a finding it does not know, naming what it takes" do
      aggregate_failures do
        expect { described_class.verdict!("maybe") }.to raise_error(described_class::UnknownVerdict, 'verdict must be accept or strike, not "maybe"')
        expect { described_class.find!(findings, "f9", plan: "001.00") }.to raise_error(described_class::NotFound, "001.00 has no finding f9")
        expect(described_class.find!(findings, "f2", plan: "001.00")).to eq(findings.last)
      end
    end

    it "is the one table the arbitrator's ruling vocabulary reads the finding kind from" do
      expect(OpenLanes::Arbitration::Ruling::OUTCOMES.fetch("finding")).to eq(%w[struck upheld])
    end
  end

  it "reads a folder with no pull-requests.md as having no findings", :tree do
    plans { |t| t.plan "001.00", :building, "work" }
    expect(described_class.for(OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first.feature.path)).to eq([])
  end
end

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

  it "reads a folder with no pull-requests.md as having no findings", :tree do
    plans { |t| t.plan "001.00", :building, "work" }
    expect(described_class.for(OpenLanes::Plans::Tree.new(dir: plans_root).subjects.first.feature.path)).to eq([])
  end
end

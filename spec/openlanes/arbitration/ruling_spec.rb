# frozen_string_literal: true

RSpec.describe OpenLanes::Arbitration::Ruling do
  def answer(yaml) = "I read the diff and the review.\n\n```ruling\n#{yaml}```\n"

  described_class::OUTCOMES.each do |kind, outcomes|
    outcomes.each do |outcome|
      it "reads #{kind} / #{outcome}" do
        ruling = described_class.parse(answer("kind: #{kind}\npr: 12\noutcome: #{outcome}\nreason: because\n"))
        expect([ruling.kind, ruling.pr, ruling.outcome, ruling.reason]).to eq([kind, 12, outcome, "because"])
      end
    end
  end

  it "reads struck and critical findings, upper-cased" do
    ruling = described_class.parse(answer(<<~YAML))
      kind: appeal
      pr: 3
      outcome: struck
      findings:
        struck: [f2]
        critical: [F1]
      reason: F2 asks for a test the spec rules out
    YAML
    expect([ruling.struck, ruling.critical, ruling.findings]).to eq([%w[F2], %w[F1], { "struck" => %w[F2], "critical" => %w[F1] }])
  end

  it "keeps a struck finding's heading beside its id" do
    ruling = described_class.parse(answer(<<~YAML))
      kind: appeal
      outcome: struck
      findings:
        struck: ["F2 lib/a.rb:10 asks for a test the spec rules out", "F3: cosmetic"]
      reason: out of scope
    YAML
    expect([ruling.struck, ruling.headings]).to eq([%w[F2 F3], { "F2" => "lib/a.rb:10 asks for a test the spec rules out", "F3" => "cosmetic" }])
  end

  it "takes a dispute's winner as its outcome" do
    ruling = described_class.parse(answer("kind: dispute\nwinner: rey-frontend\nreason: the code wins\n"))
    expect([ruling.outcome, ruling.winner]).to eq(%w[rey-frontend rey-frontend])
  end

  it "opens the engine's comment with the kind and outcome" do
    expect(described_class.parse(answer("kind: cap\noutcome: no_go\nreason: r\n")).headline).to eq("⚖️ Ruling (cap): no_go")
  end

  it "refuses an answer with no ruling block" do
    expect { described_class.parse("I rule go.") }.to raise_error(described_class::Missing)
  end

  it "refuses two ruling blocks" do
    text = answer("kind: cap\noutcome: go\nreason: a\n") + answer("kind: cap\noutcome: no_go\nreason: b\n")
    expect { described_class.parse(text) }.to raise_error(described_class::Ambiguous, /2/)
  end

  it "refuses a block that is not a mapping" do
    expect { described_class.parse(answer("- go\n")) }.to raise_error(described_class::Ambiguous)
  end

  it "refuses a block that is not YAML" do
    expect { described_class.parse(answer("kind: [cap\n")) }.to raise_error(described_class::Ambiguous)
  end

  it "refuses an outcome its kind cannot give" do
    expect { described_class.parse(answer("kind: cap\noutcome: struck\nreason: r\n")) }
      .to raise_error(described_class::IllegalOutcome, /cap cannot rule "struck"/)
  end

  it "refuses an unknown kind" do
    expect { described_class.parse(answer("kind: drift\noutcome: go\nreason: r\n")) }
      .to raise_error(described_class::IllegalOutcome, /unknown/)
  end

  it "is reached through the facade" do
    expect(OpenLanes::Arbitration.ruling(answer("kind: cap\noutcome: go\nreason: r\n")).outcome).to eq("go")
  end
end

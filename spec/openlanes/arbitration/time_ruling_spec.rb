# frozen_string_literal: true

RSpec.describe OpenLanes::Arbitration::TimeRuling do
  def parse(text) = OpenLanes::Arbitration.time_ruling(text)

  def block(yaml) = "Read the plan.\n\n```extension\n#{yaml}\n```\n"

  it "reads a grant, in minutes, as seconds" do
    ruling = parse(block("decision: grant\nminutes: 30\nreason: Two units remain."))
    expect([ruling.granted?, ruling.seconds, ruling.reason]).to eq([true, 1800, "Two units remain."])
  end

  it "reads a decline as no time" do
    ruling = parse(block("decision: decline\nreason: It is looping."))
    expect([ruling.granted?, ruling.seconds, ruling.reason]).to eq([false, 0, "It is looping."])
  end

  it "refuses an answer with no block, or with two" do
    aggregate_failures do
      expect { parse("Grant it.") }.to raise_error(OpenLanes::Arbitration::Ruling::Missing, /no ```extension block/)
      expect { parse(block("decision: decline") * 2) }.to raise_error(OpenLanes::Arbitration::Ruling::Ambiguous, /2 ```extension blocks/)
    end
  end

  it "refuses a block that is not a YAML mapping" do
    aggregate_failures do
      expect { parse(block("- grant")) }.to raise_error(OpenLanes::Arbitration::Ruling::Ambiguous, /not a YAML mapping/)
      expect { parse(block("decision: [grant")) }.to raise_error(OpenLanes::Arbitration::Ruling::Ambiguous, /not YAML/)
    end
  end

  it "refuses a decision it does not know, and a grant with no time" do
    aggregate_failures do
      expect { parse(block("decision: maybe")) }.to raise_error(OpenLanes::Arbitration::Ruling::IllegalOutcome, /cannot rule "maybe"/)
      expect { parse(block("decision: grant\nminutes: 0")) }.to raise_error(OpenLanes::Arbitration::Ruling::IllegalOutcome, /needs `minutes:`/)
      expect { parse(block("decision: grant")) }.to raise_error(OpenLanes::Arbitration::Ruling::IllegalOutcome, /needs `minutes:`/)
    end
  end
end

# frozen_string_literal: true

RSpec.describe OpenLanes::Config, "#review_gate" do
  def parse(yaml) = described_class.parse(yaml, path: ".openlanes.yml")

  it "is on, with the gate's own timeout, when the file says nothing" do
    config = parse("jobs: 2\n")
    expect([config.review_gate, config.review_gate_timeout]).to eq([true, nil])
  end

  it "reads review.gate: false and review.gate_timeout" do
    config = parse("review:\n  gate: false\n  gate_timeout: 120\n")
    expect([config.review_gate, config.review_gate_timeout]).to eq([false, 120])
  end

  it "keeps review.adapters beside the gate keys" do
    expect(parse("review:\n  adapters: [claude]\n  gate: true\n").review_adapters).to eq(%w[claude])
  end

  it "refuses a gate that is not true or false" do
    expect { parse("review:\n  gate: sometimes\n") }.to raise_error(OpenLanes::Error, /review.gate: "sometimes"/)
  end

  it "refuses a timeout that is not a positive number" do
    expect { parse("review:\n  gate_timeout: 0\n") }.to raise_error(OpenLanes::Error, /review.gate_timeout: 0/)
  end

  it "writes the gate back, on by default, and reads it again" do
    expect(parse(described_class.new.to_yaml)).to have_attributes(review_gate: true, review_gate_timeout: nil)
    written = described_class.new(review_gate: false, review_gate_timeout: 60).to_yaml
    expect(parse(written)).to have_attributes(review_gate: false, review_gate_timeout: 60)
  end
end

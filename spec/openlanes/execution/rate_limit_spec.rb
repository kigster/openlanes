# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::RateLimit do
  let(:failed) { instance_double(Process::Status, success?: false) }
  let(:ok) { instance_double(Process::Status, success?: true) }

  def transcript(error: nil, plain: [], failed: true)
    instance_double(OpenLanes::Execution::Transcript, error:, plain:, failed?: failed)
  end

  describe ".detect" do
    {
      "HTTP 429 Too Many Requests"                           => :rate_limited,
      '{"type":"error","error":{"type":"rate_limit_error"}}' => :rate_limited,
      '{"type":"error","error":{"type":"overloaded_error"}}' => :overloaded,
      "API Error: 529 Overloaded"                            => :overloaded
    }.each do |said, kind|
      it "reads #{said.inspect} as #{kind}" do
        expect(described_class.detect(failed, transcript(error: said)).kind).to eq(kind)
      end
    end

    it "finds it in the plain lines too" do
      expect(described_class.detect(failed, transcript(plain: ["working", "Error: rate limited"])).line).to eq("Error: rate limited")
    end

    it "honours retry_after when the provider gives it" do
      said = '{"error":{"type":"rate_limit_error"},"retry_after": 42}'
      expect(described_class.detect(failed, transcript(error: said)).retry_after).to eq(42)
    end

    it "answers nil for a failure that is not about load" do
      expect(described_class.detect(failed, transcript(error: "tests failed: 3 examples"))).to be_nil
    end

    it "answers nil for a run that succeeded" do
      expect(described_class.detect(ok, transcript(error: nil, plain: ["429 lines changed"], failed: false))).to be_nil
    end
  end

  describe "#delay" do
    let(:limit) { described_class.new(kind: :rate_limited, retry_after: nil, line: "429") }
    let(:still) { Struct.new(:value) { def rand = value }.new(0.0) }

    it "grows with each attempt and stops at the cap" do
      delays = [1, 2, 3, 10].map { limit.delay(it, rng: still) }
      expect(delays).to eq([30.0, 60.0, 120.0, described_class::CAP])
    end

    it "adds at most a quarter more at random" do
      expect(limit.delay(1, rng: Struct.new(:value) { def rand = value }.new(1.0))).to eq(37.5)
    end

    it "waits exactly what the provider asked for" do
      expect(limit.with(retry_after: 7).delay(5)).to eq(7.0)
    end

    it "says on the board how long it waits" do
      expect(limit.phrase(29.6)).to eq("rate-limited, retry in 30s")
    end
  end
end

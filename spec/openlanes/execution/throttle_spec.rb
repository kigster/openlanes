# frozen_string_literal: true

# Plan 060.00, item 4: telling a provider's "not now" from an agent's own
# failure, by the words every CLI leaves behind.
RSpec.describe OpenLanes::Execution::Throttle do
  subject(:limit) { described_class.detect(status, transcript) }

  let(:status) { instance_double(Process::Status, success?: false, exitstatus: 1) }
  let(:transcript) { double("transcript", failed?: !error.nil?, error:, plain:) } # rubocop:disable RSpec/VerifiedDoubles
  let(:error) { nil }
  let(:plain) { [] }

  context "when the CLI reported a 429" do
    let(:error) { %(API Error: 429 {"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}) }

    it "is a rate limit" do
      expect([limit.kind, limit.retry_after, limit.to_s]).to eq([:rate_limit, nil, "rate limited"])
    end
  end

  context "when the CLI reported repeated overloads" do
    let(:error) { "API Error: Repeated 529 Overloaded errors" }

    it "is an overload" do
      expect([limit.kind, limit.to_s]).to eq([:overloaded, "provider overloaded"])
    end
  end

  context "when the CLI died on stderr with no error event" do
    let(:plain) { ["starting", "stream error: Too Many Requests; retry-after: 12"] }

    it "reads its last words, and the wait it was told" do
      expect([limit.kind, limit.retry_after]).to eq([:rate_limit, 12.0])
    end
  end

  context "when the provider names its wait in words" do
    let(:error) { "RESOURCE_EXHAUSTED: quota hit. Please retry in 2 minutes." }

    it "turns it into seconds" do
      expect(limit.retry_after).to eq(120.0)
    end
  end

  # "retry after 2 minutes" was read as the header is, a bare number of
  # seconds, and waited two (PR 204).
  it "reads a unit after `retry after`, and a bare number as seconds" do
    asked = ["Rate limited: retry after 2 minutes.", "please retry after 90s", "Retry-After 7", "retry-after: 20\nmore to follow"]

    expect(asked.map { described_class.retry_after(it) }).to eq([120.0, 90.0, 7.0, 20.0])
  end

  context "when the wait is in milliseconds" do
    let(:error) { "rate limit reached, try again in 500ms" }

    it "does not take them for minutes" do
      expect(limit.retry_after).to eq(0.5)
    end
  end

  context "when the wait is in seconds" do
    let(:error) { "429 Too Many Requests. Please retry in 34.5 seconds." }

    it "takes the number as it stands" do
      expect(limit.retry_after).to eq(34.5)
    end
  end

  context "when the wait is in hours" do
    let(:error) { "usage limit reached, try again in 2 hours" }

    it "counts an hour as 3600 seconds" do
      expect(limit.retry_after).to eq(7200.0)
    end
  end

  context "when the invocation failed at something else" do
    let(:error) { "401 API key is invalid" }

    it { is_expected.to be_nil }
  end

  context "when only an earlier line mentioned a 429" do
    let(:plain) { ["GET /orders -> 429", "one", "two", "segfault"] }

    it { is_expected.to be_nil }
  end

  context "when the invocation succeeded while talking about rate limits" do
    let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
    let(:plain) { ["added a 429 rate limit to the API"] }

    it { is_expected.to be_nil }
  end
end

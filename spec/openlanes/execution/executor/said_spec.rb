# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Executor::Said do
  def transcript(failed: false, error: nil, plain: [])
    instance_double(OpenLanes::Execution::Transcript, failed?: failed, error:, plain:)
  end

  it "gives the error of a session that failed" do
    expect(described_class.of(transcript(failed: true, error: "401 bad key"))).to eq("401 bad key")
  end

  it "gives the last three plain lines of one that did not" do
    expect(described_class.of(transcript(plain: %w[one two three four]))).to eq("two three four")
  end

  it "says so when the session said nothing" do
    expect(described_class.of(transcript)).to eq("said nothing")
  end

  it "clips a long answer to the report's limit" do
    clipped = described_class.of(transcript(plain: ["x" * 400]))
    expect([clipped.length, clipped]).to match([OpenLanes::Execution::Executor::REASON_LIMIT + 2, end_with("...")])
  end
end

# frozen_string_literal: true

RSpec.describe OpenLanes::Apps::Status do
  let(:at) { Time.utc(2026, 10, 14, 12, 0, 0) }

  def status(**rest) = described_class.new(plan: "012.00", branch: "kig/012.00-app", process: "web", state: "ready", port: 11_101, at:, **rest)

  it "is the wire's <app> object" do
    expect(status(preview: true, framing: :frame).to_h).to eq(
      "plan"    => "012.00",
      "branch"  => "kig/012.00-app",
      "process" => "web",
      "state"   => "ready",
      "port"    => 11_101,
      "preview" => true,
      "url"     => "http://127.0.0.1:11101/",
      "framing" => "frame",
      "reason"  => nil,
      "at"      => "2026-10-14T12:00:00Z"
    )
  end

  it "keeps a url it is given" do
    expect(status(url: "http://127.0.0.1:11101/up").url).to eq("http://127.0.0.1:11101/up")
  end

  it "refuses a state that is not one of STATES" do
    expect { status(state: "running") }.to raise_error(ArgumentError, /running/)
  end

  it "says whether it is ready or failed" do
    expect([status.ready?, status(state: "failed").failed?, status(state: "starting").ready?]).to eq([true, true, false])
  end
end

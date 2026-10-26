# frozen_string_literal: true

# `mail send` with Redis and without (plan 003, B3). `state.json` is written
# first either way; the stream is a second delivery, never the record.
RSpec.describe OpenLanes::CLI::Mail::Send, :tree do
  let!(:folder) do
    path = nil
    plans { |t| path = t.plan "003.00", :building, "paired", files: { "spec.md" => spec_body, "plan.md" => "# P" } }
    path
  end

  let(:store) { OpenLanes::Live::MemoryStore.new }

  def deliver
    out = CapturedStream.new
    err = CapturedStream.new
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      described_class.new.call(dir: plans_root, body: "contract is up", plan: "003", from: "backend-coder", to: "frontend-coder")
    ensure
      $stdout, $stderr = original_out, original_err
    end
    [strip_ansi(out.string), strip_ansi(err.string)]
  end

  def bodies = OpenLanes::Plans::PlanState.for(folder).messages.map { it["body"] }

  context "when Redis answers" do
    let(:keys) { OpenLanes::Live.keys(root: File.dirname(plans_root)) }

    before { allow(OpenLanes::Live).to receive(:connect).and_return(store) }

    it "writes state.json and publishes the message for the plans directory's checkout" do
      deliver

      aggregate_failures do
        expect(bodies).to eq(["contract is up"])
        expect(OpenLanes::Live::Mail.new(store:, keys:).drain(plan: "003.00", consumer: "harness"))
          .to contain_exactly(include("number" => 1, "from" => "backend-coder", "body" => "contract is up"))
      end
    end
  end

  context "when Redis is unavailable" do
    before do
      allow(OpenLanes::Live).to receive(:connect).and_raise(OpenLanes::Live::Unavailable, "Redis at redis://h/0 is unavailable")
    end

    it "still finds the message in state.json, and says nothing about Redis" do
      out, err = deliver

      aggregate_failures do
        expect(bodies).to eq(["contract is up"])
        expect(out).to eq("")
        expect(err).to include("#1 → frontend-coder")
        expect(err).not_to include("Redis")
      end
    end
  end
end

# frozen_string_literal: true

# `openlanes state estimate`, as an agent told ESTIMATE runs it.
RSpec.describe OpenLanes::CLI::State::Estimate, :tree do
  let(:state) { OpenLanes::Plans::PlanState.for(Dir[File.join(plans_root, "001.00*")].first) }

  before do
    plans { |t| t.plan "001.00", :building, "work", files: { "spec.md" => spec_body, "plan.md" => "## U" } }
  end

  # What it wrote on STDERR, and its exit status.
  def estimate(**)
    original = $stderr
    $stderr = CapturedStream.new
    described_class.new.call(dir: plans_root, plan: "001", agent: "backend-coder", **)
    [strip_ansi($stderr.string), 0]
  rescue SystemExit => e
    [strip_ansi($stderr.string), e.status]
  ensure
    $stderr = original
  end

  def asked(stage: "estimate") = state.ask_extension!(agent: "backend-coder", state: "building", round: 1, limit: "time", stage:)

  it "is registered where every agent's grant already reaches: under `state`" do
    expect(OpenLanes::Config::CommandsSchema.commands(OpenLanes::CLI)).to include("state estimate" => described_class)
  end

  it "writes the estimate onto the request that asked, and says so" do
    asked
    err, status = estimate(minutes: "20", why: "two units left")
    aggregate_failures do
      expect([status, err]).to match([0, a_string_including("backend-coder: 20 more minutes asked for", "state.json")])
      expect(state.extensions.first).to include("estimate" => 1200, "why" => "two units left", "stage" => "estimate")
      expect(state.extensions.first).not_to have_key("settled_at")
    end
  end

  it "takes a second answer over the first while the engine still waits" do
    asked
    estimate(minutes: "20")
    estimate(minutes: "1h", quiet: true)
    expect(state.extensions.first).to include("estimate" => 3600)
  end

  it "refuses a time it cannot read, and records nothing" do
    asked
    err, status = estimate(minutes: "about half an hour")
    expect([status, err, state.extensions.first.key?("estimate")]).to match([64, a_string_including("is not a time above zero"), false])
  end

  it "refuses when nobody asked, or the engine has stopped waiting" do
    asked(stage: "person")
    err, status = estimate(minutes: "20")
    expect([status, err]).to match([64, a_string_including("Nobody is waiting on an estimate from backend-coder")])
  end

  it "refuses another agent's request" do
    asked
    _err, status = estimate(agent: "frontend-coder", minutes: "20")
    expect(status).to eq(64)
  end
end

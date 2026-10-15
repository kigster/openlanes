# frozen_string_literal: true

# `openlanes state` is what every agent shells out to at the start and end of
# its round, so it is exercised the way an agent uses it.
RSpec.describe "openlanes state", :tree do
  before do
    plans { |t| t.plan "001.00", :building, "work", files: { "spec.md" => spec_body, "plan.md" => "## U" } }
  end

  def run(command, **)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(dir: plans_root, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  def sign(**) = run(OpenLanes::CLI::State::Sign.new, **)

  def show(**) = run(OpenLanes::CLI::State::Show.new, **)

  def resume(**) = run(OpenLanes::CLI::State::Resume.new, **)

  it "signs, and says where" do
    _out, err, status = sign(plan: "001", agent: "luke-backend", round: "1", status: "Completed", next: "hansolo-reviewer")
    expect([status, err]).to match([0, a_string_including("luke-backend: Completed, round 1", "state.json")])
  end

  it "prints the document as JSON on STDOUT" do
    sign(plan: "001", agent: "luke-backend", round: "1", status: "Started")
    out, = show(plan: "001")
    expect(JSON.parse(out)["signatures"].map { |s| s["status"] }).to eq(["Started"])
  end

  # Decision N3: an archived plan is still a plan; `--plan` finds it there.
  it "shows a plan that has moved into archive/" do
    plans do |t|
      t.plan "002.00", :approved, "shipped", under: "archive", archived_on: Date.new(2026, 9, 1), files: { "spec.md" => spec_body }
    end
    _out, err, status = show(plan: "002")

    expect([status, err]).to eq([0, ""])
  end

  it "refuses a round that is not a number" do
    _out, err, status = sign(plan: "001", agent: "luke-backend", round: "one", status: "Started")
    expect([status, err]).to match([64, a_string_including("--round must be a number")])
  end

  it "refuses a handoff after Blocked" do
    _out, err, status = sign(plan: "001", agent: "luke-backend", round: "1", status: "Blocked", next: "x")
    expect([status, err]).to match([64, a_string_including("only a Completed")])
  end

  it "refuses a plan the tree does not hold" do
    _out, err, status = show(plan: "009")
    expect([status, err]).to match([66, a_string_including("No plan 009")])
  end

  it "signs quietly when asked" do
    _out, err, = sign(plan: "001", agent: "luke-backend", round: "1", status: "Started", quiet: true)
    expect(err).to be_empty
  end

  describe "resume" do
    let(:folder) { Dir[File.join(plans_root, "001.00*")].first }

    it "writes an agent resume record into state.json" do
      _out, err, status = resume(plan: "001",
        agent: "luke-backend",
        round: "2",
        status: "Interrupted",
        done: "B1, B2",
        remaining: "B3",
        next_step: "run rspec",
        files: "lib/a.rb,lib/b.rb")
      entry = OpenLanes::Plans::PlanState.for(folder).last_known("luke-backend")

      aggregate_failures do
        expect([status, err]).to match([0, a_string_including("luke-backend: Interrupted, round 2, resume record")])
        expect(entry.to_h).to include(source: "agent",
          round: 2,
          done: %w[B1 B2],
          remaining: ["B3"],
          next_step: "run rspec",
          files_touched: %w[lib/a.rb lib/b.rb])
      end
    end

    it "refuses a round that is not a number" do
      _out, err, status = resume(plan: "001", agent: "luke-backend", round: "x", status: "Interrupted")
      expect([status, err]).to match([64, a_string_including("--round must be a number")])
    end

    it "refuses an agent name that is not one token" do
      _out, err, status = resume(plan: "001", agent: "two words", round: "1", status: "Interrupted")
      expect([status, err]).to match([64, a_string_including("agent name")])
    end

    it "records quietly when asked" do
      _out, err, status = resume(plan: "001", agent: "luke-backend", round: "1", status: "Interrupted", quiet: true)
      expect([status, err]).to eq([0, ""])
    end
  end
end

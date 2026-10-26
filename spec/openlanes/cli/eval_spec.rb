# frozen_string_literal: true

# `openlanes eval` scores recordings by default and runs agents only when
# told to. These pin the report, the filters, the exit status a CI job reads,
# and that nothing here ever reaches a real agent.
RSpec.describe OpenLanes::CLI::Eval, :tree do
  subject(:result) { invoke(**options) }

  let(:options) { {} }

  def invoke(**)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      described_class.new.call(**)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end
    { out: strip_ansi(out.string), err: unwrapped(strip_ansi(err.string)), status: }
  end

  describe "offline, over the shipped cases" do
    it "passes every pass/ recording and exits 0" do
      expect([result[:status], result[:out].scan("PASS").size, result[:out].scan("FAIL").size])
        .to eq([0, OpenLanes::Evals.cases.size, 0])
    end

    it "prints the table on STDOUT" do
      expect(result[:out]).to include("Case", "Agent", "Depth", "Checks", "research-fast", "researcher")
    end

    context "with --recording fail" do
      let(:options) { { recording: "fail" } }

      it "fails every case, explains each, and exits 1" do
        expect([result[:status], result[:out]]).to match([1, %r{chores-coder/task-fast FAIL\n  - changed files 1..2 @fast: 3 files changed}])
      end
    end

    context "with --agent" do
      let(:options) { { agent: "chores-coder" } }

      it "scores only that agent's cases" do
        expect(result[:out].scan(/^│ \S+/).map { it.delete_prefix("│ ") }).to eq(%w[Case task-fast task-medium])
      end
    end

    context "with the agent named as an argument" do
      let(:options) { { name: "chores-coder" } }

      it "scores only that agent's cases, as --agent does" do
        expect(result[:out].scan(/^│ \S+/).map { it.delete_prefix("│ ") }).to eq(%w[Case task-fast task-medium])
      end
    end

    context "with both an argument and --agent" do
      let(:options) { { name: "researcher", agent: "chores-coder" } }

      it "lets --agent win" do
        expect(result[:out]).not_to include("researcher")
      end
    end

    context "with --case and --depth" do
      let(:options) { { case: "research-fast", depth: "deep" } }

      it "holds the recording to the other depth's bounds" do
        expect([result[:status], result[:out]]).to match([1, /research-fast.*deep.*FAIL.*count .* in spec.md#Research 2..8 @deep/m])
      end
    end

    context "with a filter that matches nothing" do
      let(:options) { { agent: "nobody" } }

      it "refuses with 66" do
        expect([result[:status], result[:err]]).to match([66, /No eval case matches --agent nobody/])
      end
    end

    context "with --max-tokens but no --live" do
      let(:options) { { max_tokens: 10 } }

      it "refuses with 64: a cap on nothing is a mistake" do
        expect([result[:status], result[:err]]).to match([64, /only applies to --live/])
      end
    end
  end

  describe "a case directory of its own" do
    let(:cases_dir) { File.join(File.dirname(plans_root), "cases") }
    let(:options) { { cases: cases_dir } }

    before do
      FileUtils.mkdir_p(File.join(cases_dir, "researcher"))
      File.write(File.join(cases_dir, "researcher", "bare.yml"), case_yaml)
    end

    context "when a case is invalid" do
      let(:case_yaml) { "id: bare\nagent: researcher\ndepth: bottomless\n" }

      it "refuses with 65, naming the problem" do
        expect([result[:status], result[:err]]).to match([65, /depth "bottomless"/])
      end
    end

    context "when a case has no recording" do
      let(:case_yaml) do
        "id: bare\nagent: researcher\ndepth: fast\nfixture: {state: new, files: {spec.md: x}}\nexpect: {signed: true}\n"
      end

      it "skips it and says so" do
        expect([result[:status], result[:err]]).to match([0, %r{researcher/bare has no pass/ recording, skipped}])
      end
    end
  end

  describe "--live" do
    let(:kase) { OpenLanes::Evals.cases.find { it.id == "task-fast" } }
    let(:score) { OpenLanes::Evals::Score.new(kase:, verdicts: [OpenLanes::Evals::Verdict.new(name: "x", ok: true, detail: "")]) }
    let(:spent) do
      OpenLanes::Execution::Executor::Result.new(ok: true,
        note: "completed",
        up: 900,
        down: 100,
        subagents: 0,
        delegated: 0,
        seconds: 42.4)
    end
    let(:options) { { live: true, case: "task-fast" } }

    before do
      allow(OpenLanes::Evals).to receive(:run_live)
        .and_return(OpenLanes::Evals::Live::Outcome.new(score:, result: spent, root: nil))
    end

    it "runs the case under the default cap" do
      result
      expect(OpenLanes::Evals).to have_received(:run_live).with(kase, max_tokens: 300_000)
    end

    it "reports what the run spent" do
      expect(result[:out]).to match(/task-fast.*42.*1000.*PASS/)
    end

    context "with --max-tokens" do
      let(:options) { { live: true, case: "task-fast", max_tokens: 50_000 } }

      it "passes the tighter cap through" do
        result
        expect(OpenLanes::Evals).to have_received(:run_live).with(kase, max_tokens: 50_000)
      end
    end
  end
end

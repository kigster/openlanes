# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::RemovalCommand, :tree do
  let(:command) { OpenLanes::CLI::Trash.new }

  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root, all: true) }
  let(:open_pr) { "| Pull Request Number | Pull Request Name | Status |\n| -: | :- | -: |\n| 12 | [x](https://github.com/o/r/pull/12) | Open 🟢 |\n" }

  before do
    plans do |t|
      t.plan "001.00", :planned, "waiter", files: { "spec.md" => "---\ndepends_on: [\"002.00\"]\n---\n#{spec_body}" }
      t.plan "002.00", :ready_for_review, "stale", files: { "spec.md" => "---\ndepends_on: [\"003.00\"]\n---\n#{spec_body}", "plan.md" => "## U\n", "pull-requests.md" => open_pr }
      t.plan "003.00", :new, "base", files: { "spec.md" => spec_body }
    end
  end

  def exit_status
    yield
    0
  rescue SystemExit => e
    e.status
  end

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    status = exit_status { command.call(dir: plans_root, **) }
    [strip_ansi(out.string), strip_ansi(err.string), status]
  ensure
    $stdout, $stderr = original_out, original_err
  end

  def state(ordinal) = tree.reload.find(ordinal).status.key

  it "applies --reason to every plan and asks nothing" do
    allow(command).to receive(:prompt)
    _, _, status = run(ids: %w[002 003], reason: "done elsewhere")
    expect(command).not_to have_received(:prompt)
    expect(status).to eq(0)
    expect([state("002.00"), state("003.00")]).to all(eq(:trashed))
    expect(tree.find("003.00").read("trashed-reason.md")).to include("done elsewhere")
  end

  it "names each rewrite and each open pull request" do
    out, = run(ids: %w[002], reason: "x")
    expect(out).to include("001.00: 002.00 → 003.00", "#12")
  end

  it "moves nothing when an id is unknown" do
    _, err, status = run(ids: %w[002 999], reason: "x")
    expect(status).not_to eq(0)
    expect(err).to include("999")
    expect(state("002.00")).to eq(:ready_for_review)
  end

  it "moves nothing without a terminal or a reason" do
    allow(command).to receive(:tty?).and_return(false)
    _, err, status = run(ids: %w[002])
    expect(status).not_to eq(0)
    expect(err).to include("--reason")
    expect(state("002.00")).to eq(:ready_for_review)
  end

  it "refuses a blank --reason" do
    _, _, status = run(ids: %w[002], reason: "  ")
    expect(status).not_to eq(0)
    expect(state("002.00")).to eq(:ready_for_review)
  end

  it "collects every answer before the first write" do
    interview = instance_double(OpenLanes::Lifecycle::ReasonInterview)
    allow(command).to receive_messages(tty?: true, prompt: instance_double(TTY::Prompt))
    allow(OpenLanes::Lifecycle).to receive(:reason_interview).and_return(interview)
    allow(interview).to receive(:ask) do
      expect(state("002.00")).to eq(:ready_for_review)
      raise TTY::Reader::InputInterrupt
    end
    _, _, status = run(ids: %w[002 003])
    expect(status).not_to eq(0)
    expect(state("003.00")).to eq(:new)
  end

  it "does not ask about a plan already there" do
    run(ids: %w[003], reason: "first")
    interview = instance_double(OpenLanes::Lifecycle::ReasonInterview, ask: {})
    allow(command).to receive_messages(tty?: true, prompt: instance_double(TTY::Prompt))
    allow(OpenLanes::Lifecycle).to receive(:reason_interview).and_return(interview)
    run(ids: %w[003])
    expect(interview).to have_received(:ask).with([])
  end

  it "writes nothing on a dry run, needing neither a reason nor a terminal" do
    allow(command).to receive(:tty?).and_return(false)
    before = Dir.glob("**/*", base: plans_root).sort
    out, err, status = run(ids: %w[002], dry_run: true)
    expect(status).to eq(0)
    expect(out).to include("001.00: 002.00 → 003.00")
    expect(err).to include("nothing was changed")
    expect(Dir.glob("**/*", base: plans_root).sort).to eq(before)
  end

  it "exits non-zero when a plan was refused, having handled the rest" do
    OpenLanes::Plans::Lock.write(tree.find("002.00").feature.path)
    _, err, status = run(ids: %w[002 003], reason: "x")
    expect(status).not_to eq(0)
    expect(err).to include("002.00")
    expect(state("003.00")).to eq(:trashed)
  end

  describe "the registry" do
    def resolved(*argv) = OpenLanes::CLI.get(argv).command

    it "keeps bare plans and plans --all as the table" do
      expect(resolved("plans")).to be_a(OpenLanes::CLI::ListPlans).or eq(OpenLanes::CLI::ListPlans)
      expect(resolved("plans", "--all")).to be_a(OpenLanes::CLI::ListPlans).or eq(OpenLanes::CLI::ListPlans)
    end

    { "abandon" => OpenLanes::CLI::Abandon, "discard" => OpenLanes::CLI::Discard, "trash" => OpenLanes::CLI::Trash }.each do |word, klass|
      it "routes plans #{word}" do
        expect(resolved("plans", word, "001")).to be_a(klass).or eq(klass)
      end
    end
  end
end

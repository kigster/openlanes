# frozen_string_literal: true

# `openlanes unblock 031` printed nothing at all: not what it
# found, not what it did, not that it had started. It was handing the folder
# to an agent that can take a quarter of an hour and saying nothing until the
# agent came back, so a run that had nothing to do and a run still working
# looked exactly alike. Every example here asserts that some case *says* which
# case it is.
RSpec.describe OpenLanes::CLI::Unblock, :tree do
  subject(:command) { described_class.new }

  let(:blocked_body) do
    <<~MARKDOWN
      # Blocked

      ## B1. Which vendor

      ## B2. What happens on revocation

      ## A2. Retain, do not delete

      Decided by Alan Turing <alan.turing@manchester.edu>, 2026-08-01.
    MARKDOWN
  end

  def blocked_plan(ordinal = "001.00", body: blocked_body)
    plans { |t| t.plan(ordinal, :blocked, "plaid-integration", files: { "spec.md" => spec_body, "blocked.md" => body }) }
  end

  # Everything the user sees that is not the deliverable goes to STDERR, so a
  # command still composes in a pipe. Both halves are captured, separately.
  def run(*plans, **)
    out = CapturedStream.new
    err = CapturedStream.new
    status = 0

    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(plans:, dir: plans_root, dry_run: true, **)
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = original_out, original_err
    end

    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  # The boxes wrap on words at the terminal's width, so a sentence assertion
  # has to read them back unwrapped or it passes and fails by screen size.

  # The real run is the path that was silent, and it is the path that shells out.
  # The executor is replaced so the suite never invokes `claude`.
  def with_executor(result: [true, "completed"], &edit)
    executor = instance_double(OpenLanes::Execution::Executor)
    allow(executor).to receive(:call) do |_agent, subject, **|
      edit&.call(subject)
      result
    end
    allow(OpenLanes::Execution::Executor).to receive(:new).and_return(executor)
  end

  describe "a plan that is not there" do
    it "says which number it could not find" do
      blocked_plan
      _out, err, = run("999")

      expect(unwrapped(err)).to include("999", "no plan of that number")
    end

    it "says what the tree does hold, so the typo is obvious" do
      blocked_plan
      _out, err, = run("999")

      expect(err).to include("001.00")
    end

    it "exits non-zero rather than looking like a run with nothing to do" do
      blocked_plan

      expect(run("999").last).to eq(66)
    end

    it "still drains the plans that were found" do
      blocked_plan
      out, = run("999", "001")

      expect(out).to include("001.00")
    end
  end

  describe "a plan that was never blocked" do
    before { plans { |t| t.plan("002.00", :new, "unstopped", files: { "spec.md" => spec_body }) } }

    it "says the folder has no blocked.md rather than saying nothing" do
      _out, err, = run("002")

      expect(unwrapped(err)).to include("nothing to drain")
    end

    it "exits non-zero" do
      expect(run("002").last).to eq(65)
    end
  end

  describe "a dry run" do
    before { blocked_plan }

    it "names every question still open, before anything is invoked" do
      _out, err, = run("001")

      expect(err).to include("B1. Which vendor", "B2. What happens on revocation")
    end

    it "marks the ones with an answer sitting unfolded" do
      _out, err, = run("001")

      expect(err).to include("← answer waiting")
    end

    it "counts them, so the shape is readable without reading the list" do
      _out, err, = run("001")

      expect(err).to include("2 open, 1 with an answer waiting")
    end

    it "says plainly that nothing was invoked and nothing changed" do
      _out, err, = run("001")

      expect(unwrapped(err)).to include("Dry run", "without --dry-run")
    end

    it "puts the machine-readable line on STDOUT and nothing else there" do
      out, = run("001")

      expect(out.lines.map(&:chomp)).to eq(["001.00\tblocked\t2 open\tnot attempted\tdry run - would invoke lando-broker"])
    end

    it "exits zero, because a preview is not a failure" do
      expect(run("001").last).to eq(0)
    end
  end

  describe "a blocked plan with nothing answered yet" do
    before { blocked_plan("003.00", body: "# Blocked\n\n## B1. Which vendor\n") }

    it "says so before an agent is spent on it" do
      _out, err, = run("003")

      expect(err).to include("1 open, none answered yet")
    end
  end

  describe "a blocked.md no program can read" do
    before { blocked_plan("004.00", body: "# Blocked\n\n## Question one\n") }

    it "explains why nothing can be drained from it" do
      _out, err, = run("004")

      expect(err).to include("names no `## B<n>` question")
    end

    it "says what to do about it" do
      _out, err, = run("004")

      expect(err).to include("Number each open question")
    end
  end

  describe "without --dry-run" do
    before { blocked_plan }

    # The bug, stated as a property: whatever happens, the command says
    # something about it.
    it "is never silent" do
      with_executor
      out, err, = run("001", dry_run: false)

      expect(out + err).not_to be_empty
    end

    it "names each question it folded in, by number" do
      with_executor { |subject| fold(subject, 2) }
      out, err, = run("001", dry_run: false)

      expect(out + err).to include("folded B2")
    end

    it "reports what is still waiting on a human" do
      with_executor { |subject| fold(subject, 2) }
      _out, err, = run("001", dry_run: false)

      expect(unwrapped(err)).to include("1 still waiting on a human")
    end

    it "says the block is retired once the last question goes" do
      with_executor { |subject| fold(subject, 1, 2) }
      out, err, = run("001", dry_run: false)

      expect(out + err).to include("blocked.md retired")
    end

    # A partial drain is a normal, successful run.
    it "exits zero on a partial drain" do
      with_executor { |subject| fold(subject, 2) }

      expect(run("001", dry_run: false).last).to eq(0)
    end

    # Not folding anything is the outcome a human most needs explaining, since
    # it looks identical to the command not having run.
    it "explains a run that folded nothing rather than reporting a bare zero" do
      with_executor
      _out, err, = run("001", dry_run: false)

      expect(unwrapped(err)).to include("Nothing moved", "## A<n>")
    end

    it "reports a failed agent with what it said" do
      with_executor(result: [false, "claude exited 1: 401 API key is invalid"])
      _out, err, = run("001", dry_run: false)

      expect(unwrapped(err)).to include("401 API key is invalid")
    end

    it "exits non-zero when the agent failed" do
      with_executor(result: [false, "claude exited 1"])

      expect(run("001", dry_run: false).last).to eq(1)
    end
  end

  # What `lando-broker` does to `blocked.md` when it folds a question in.
  def fold(subject, *numbers)
    path = File.join(subject.feature.path, "blocked.md")
    kept = File.read(path).split(/^(?=\#\# )/).reject { |s| numbers.any? { |n| s.start_with?("## B#{n}") } }
    remaining = kept.join
    remaining.match?(OpenLanes::Plans::OPEN_BLOCK) ? File.write(path, remaining) : File.delete(path)
  end
end

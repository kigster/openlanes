# frozen_string_literal: true

require "tmpdir"

RSpec::Matchers.define_negated_matcher :not_to_output, :output

RSpec.describe OpenLanes::UI do
  # The suite never runs against a terminal, so `animate?` is false by default
  # and the examples that want animation say so explicitly.
  before { described_class.quiet = false }

  after { described_class.quiet = false }

  describe ".animate?" do
    it "is false when STDERR is not a terminal, whatever else is true" do
      allow($stderr).to receive(:tty?).and_return(false)

      expect(described_class).not_to be_animate
    end

    it "is false on a terminal when the caller asked for quiet" do
      allow($stderr).to receive(:tty?).and_return(true)
      described_class.quiet = true

      expect(described_class).not_to be_animate
    end

    it "is true only on a terminal that has not asked for quiet" do
      allow($stderr).to receive(:tty?).and_return(true)

      expect(described_class).to be_animate
    end
  end

  describe ".spinning" do
    context "when nothing is animated — a pipe, a CI log, or --quiet" do
      before { allow($stderr).to receive(:tty?).and_return(false) }

      it "returns the block's value untouched" do
        expect(described_class.spinning("working") { :the_result }).to eq(:the_result)
      end

      # The property that keeps CI logs readable: spinner frames written to a
      # file are line noise, and a CI log is a file.
      it "writes nothing at all" do
        expect { described_class.spinning("working") { :x } }.not_to output.to_stderr
      end

      it "lets an exception through rather than swallowing it" do
        expect { described_class.spinning("working") { raise ArgumentError, "boom" } }.to raise_error(ArgumentError, "boom")
      end

      # There is nowhere to draw a live line, and the block must not have to
      # ask whether there is: it reports, and the news goes to the log instead.
      it "still hands the block somewhere to report progress" do
        expect { described_class.spinning("working") { |activity| activity.call("reading spec.md") } }.not_to raise_error
      end
    end

    # Stubbed on the module rather than on `$stderr`: `output.to_stderr` swaps
    # in a stream of its own, and the stub would stay behind on the old one.
    context "on a terminal" do
      before { allow(described_class).to receive(:tty?).and_return(true) }

      it "spins while the work runs and leaves a done line behind" do
        result = nil

        aggregate_failures do
          expect { result = described_class.spinning("working") { :done } }.to output(/✓ working/).to_stderr
          expect(result).to eq(:done)
        end
      end

      # Without this the spinner keeps spinning over the backtrace, and the
      # terminal is left with a half-drawn frame.
      it "marks the line failed and re-raises when the work blows up" do
        expect {
          expect { described_class.spinning("working") { raise "boom" } }.to raise_error("boom")
        }.to output(/𝘅 working/).to_stderr
      end
    end

    # A fifteen minute agent invocation and a hung one look identical until
    # the spinner says what the agent is doing.
    describe ".activity_for" do
      let(:line) { Dry::CLI::UI::Line.new }

      it "lets the work rewrite the tail of its own line while it runs" do
        described_class.activity_for(line).call("reading spec.md")

        expect(line.detail).to include("reading spec.md")
      end

      it "leaves the tail empty until there is news" do
        described_class.activity_for(line).call(nil)

        expect(line.detail).to eq("")
      end
    end
  end

  describe ".stepping" do
    let(:items) { [1, 2, 3, 4, 5] }

    context "when nothing is animated" do
      before { allow($stderr).to receive(:tty?).and_return(false) }

      it "still yields every item, in order" do
        seen = []
        described_class.stepping(items, "working") { |i| seen << i }

        expect(seen).to eq(items)
      end

      it "writes nothing at all" do
        expect { described_class.stepping(items, "w") { |_| nil } }.not_to output.to_stderr
      end
    end

    # Stubbed on the module rather than on `$stderr`: `output.to_stderr` swaps
    # in a stream of its own, and the stub would stay behind on the old one.
    context "on a terminal" do
      before { allow(described_class).to receive(:tty?).and_return(true) }

      it "advances once per item and leaves the final count behind" do
        expect { described_class.stepping(items, "working") { |_| nil } }.to output(%r{✓ working 5/5}).to_stderr
      end

      it "returns the items, so the call can be chained" do
        expect(described_class.stepping(items, "working") { |_| nil }).to eq(items)
      end

      # A bar for two items appears and vanishes before the eye resolves it,
      # and the line it prints is longer than the work it describes.
      it "draws no bar below the threshold, but still does the work" do
        seen = []

        aggregate_failures do
          expect { described_class.stepping([1, 2], "working") { |i| seen << i } }.not_to output.to_stderr
          expect(seen).to eq([1, 2])
        end
      end
    end
  end

  # The counter that sits between the spinner and the agent's name. It is
  # redrawn several times a second, so it is padded to a fixed width: sized to
  # its numbers, it would drag the rest of the line sideways as they grow.
  # Outside the dashboard a phrase rides a one-line spinner, which is short.
  describe ".said" do
    subject { described_class.said(phrase) }

    context "with a phrase that fits" do
      let(:phrase) { "reading spec.md" }

      it { is_expected.to eq(": reading spec.md") }
    end

    context "with a phrase longer than a spinner line" do
      let(:phrase) { "x" * 200 }

      it { is_expected.to eq(": #{"x" * (described_class::SAID_LIMIT - 1)}…") }
    end

    context "without a phrase" do
      let(:phrase) { nil }

      it { is_expected.to eq("") }
    end
  end

  describe ".meter" do
    def progress(up, down) = OpenLanes::Execution::Transcript::Progress.new(activity: nil, up:, down:, subagents: 0)

    it "shows both directions" do
      expect(described_class.meter(progress(1002, 40))).to include("↑").and include("↓")
    end

    it "occupies the same width whatever the numbers are" do
      narrow = described_class.display_width(described_class.meter(progress(0, 0)))
      wide = described_class.display_width(described_class.meter(progress(9_400_000, 812_000)))

      expect(narrow).to eq(wide)
    end

    it "reads as zero before an agent has spent anything" do
      expect(described_class.meter(nil)).to include("↑0").and include("↓0")
    end
  end

  describe ".countdown" do
    it "reads minutes and seconds, the run default as 15:00" do
      expect(described_class.countdown(900)).to include("15:00")
    end

    it "occupies the same width with one minute digit as with two" do
      narrow = described_class.display_width(described_class.countdown(59))
      wide = described_class.display_width(described_class.countdown(900))

      expect(narrow).to eq(wide)
    end

    it "draws nothing for a line that has no deadline" do
      expect(described_class.countdown(nil)).to eq("")
    end

    it "turns red inside the warning window" do
      allow(described_class).to receive(:color?).and_return(true)
      calm = described_class.countdown(described_class::TIMER_WARNING + 1)
      urgent = described_class.countdown(described_class::TIMER_WARNING)

      aggregate_failures do
        expect(calm).not_to include("\e[31m")
        expect(urgent).to include("\e[31m")
      end
    end
  end

  describe "Line's countdown" do
    let(:handle) { Dry::CLI::UI::Line.new }

    # The executor's kill and the ticker's wake-up race by up to a second;
    # a clock must floor at zero rather than accuse the line of overdraft.
    it "counts down from the timeout and never below zero" do
      line = described_class::Line.new(handle:, timeout: 300)

      aggregate_failures do
        expect(line.remaining).to eq(300)
        allow(described_class).to receive(:monotonic).and_return(described_class.monotonic + 400)
        expect(line.remaining).to eq(0)
      end
    end

    it "keeps no clock when no timeout was given" do
      expect(described_class::Line.new(handle:).remaining).to be_nil
    end

    it "puts the timer on the line as soon as the line starts" do
      line = described_class::Line.new(handle:, timeout: 300)
      line.start

      expect(handle.detail).to include("5:00")
    ensure
      line.done
    end

    it "stops ticking once the line is done" do
      line = described_class::Line.new(handle:, timeout: 300)
      line.start
      line.done

      expect(line.instance_variable_get(:@ticker)).to be_nil
    end
  end

  describe ".abbreviate" do
    it "keeps small numbers exact and large ones short" do
      counts = [512, 4900, 121_000, 1_590_000, 12_000_000].map { |n| described_class.abbreviate(n) }

      expect(counts).to eq(["512", "4.9k", "121k", "1.6M", "12M"])
    end
  end

  describe ".log" do
    around do |example|
      Dir.mktmpdir { |dir|
        @log_path = File.join(dir, "sub", "run.log")
        example.run
      }
    end

    after { described_class.log_path = nil }

    it "is a no-op with nothing set" do
      expect { described_class.log("hello") }.not_to raise_error
    end

    it "appends a line in columns, creating the directory if needed" do
      described_class.log_path = @log_path
      described_class.log("editing spec.md",
        plan:    "003.00",
        status:  "⭐️ Planned",
        agent:   "yoda-writer",
        seconds: 42,
        round:   "01")

      expect(File.read(@log_path)).to match(/\A\[\d\d:\d\d:\d\d \| 003\.00 +\| ⭐️ Planned +\| yoda-writer +\| 01 \| +\d+ \| +42s\] editing spec\.md\n\z/)
    end

    it "appends rather than truncating on a second call" do
      described_class.log_path = @log_path
      described_class.log("first")
      described_class.log("second")

      lines = File.readlines(@log_path)

      aggregate_failures do
        expect(lines.size).to eq(2)
        expect(lines.last).to include("second")
      end
    end
  end

  # A block that returns normally has not necessarily succeeded: the executor
  # reports failure by returning a not-ok result rather than by raising, and
  # a line that drew ✓ "done" over a timed-out agent — directly above a round
  # table saying FAIL — contradicted itself. The `failure:` proc is how a
  # caller teaches the line to read the result.
  describe ".concurrently with a failure verdict" do
    let(:failure) { ->(result) { result if result.is_a?(String) } }

    it "marks a returned failure as one, with its reason" do
      expect {
        described_class.concurrently([:plan],
          "round",
          jobs:    1,
          label:   ->(_) { "000.00" },
          failure:) { |_| "timed out after 900s" }
      }.to output(/𝘅.*000\.00.*timed out after 900s/m).to_stderr
    end

    it "still marks a clean result as done" do
      expect {
        described_class.concurrently([:plan],
          "round",
          jobs:    1,
          label:   ->(_) { "000.00" },
          failure:) { |_| :ok }
      }.to output(/✓.*000\.00/m).to_stderr
    end

    it "logs the failure as a failure, not as finished" do
      Dir.mktmpdir("ui-log") do |dir|
        described_class.log_path = File.join(dir, "progress.log")
        described_class.concurrently([:plan],
          "round",
          jobs:    1,
          label:   ->(_) { "000.00" },
          failure:) { |_| "timed out after 900s" }

        expect(File.read(described_class.log_path)).to include("failed after", "timed out after 900s")
        expect(File.read(described_class.log_path)).not_to include("finished after")
      ensure
        described_class.log_path = nil
      end
    end
  end

  # The identity bracket between an agent's name and its activity: the round
  # from the log fields, the pid once the harness has found the child.
  describe "a line's identity bracket" do
    def update(pid: nil) = OpenLanes::Execution::Transcript::Progress.new(activity: nil, up: 0, down: 0, subagents: 0, pid:)

    it "renders round alone until the pid is known, then both, pid first" do
      line = described_class::Line.new(fields: { round: "01" })

      expect(line.identity).to include("…, round 01")
      line.call(update(pid: 36_123))
      expect(line.identity).to include("36123, round 01")
    end

    it "renders nothing for a caller with neither fact" do
      expect(described_class::Line.new.identity).to eq("")
    end
  end

  # `.concurrently` is what `Runner` drives every round through. These
  # examples are what stop `jobs <= 1 || list.size <= 1` — the exact shape a
  # `--plan NNN.MM` round takes — from silently bypassing every bit of the
  # reporting below, the way it used to.
  describe ".concurrently" do
    context "with nothing to do" do
      it "returns an empty array without touching the block" do
        expect(described_class.concurrently([], "round", jobs: 2) { raise "never" }).to eq([])
      end
    end

    context "one item, or jobs limited to one — not a terminal" do
      before { allow($stderr).to receive(:tty?).and_return(false) }

      it "still runs the block and returns its result" do
        result = described_class.concurrently([:plan], "round 1 — 1 plan", jobs: 1) { |_| :done }

        expect(result).to eq([:done])
      end

      it "prints a header line and a completion line rather than nothing at all" do
        expect { described_class.concurrently([:plan], "round 1 — 1 plan", jobs: 1, label: ->(_) { "000.00" }) { |_| :done } }.to output(/round 1.*000\.00/m).to_stderr
      end

      it "logs the start and the finish when a log path is set" do
        Dir.mktmpdir do |dir|
          described_class.log_path = File.join(dir, "run.log")
          described_class.concurrently([:plan],
            "round 1",
            jobs:   1,
            label:  ->(_) { "000.00" },
            fields: ->(_) { { plan: "000.00", agent: "yoda-writer" } }) { |_| :done }

          log = File.read(described_class.log_path)
          aggregate_failures do
            expect(log).to match(/\| 000\.00 .*yoda-writer.*\] started$/)
            expect(log).to match(/\| 000\.00 .*\] finished after \d+s$/)
          end
        end
      ensure
        described_class.log_path = nil
      end

      it "re-raises a failure after reporting it, rather than swallowing it" do
        expect { described_class.concurrently([:plan], "round", jobs: 1, label: ->(_) { "000.00" }) { |_| raise "boom" } }.to raise_error("boom")
      end

      # A spinner is not drawable here, but progress is still worth having: a
      # CI log wants to know what the agent is doing, and which plan is doing it.
      it "still hands each item somewhere to report what it is doing" do
        seen = []
        described_class.concurrently([:plan], "round", jobs: 1, label: ->(_) { "000.00" }) do |_, activity|
          seen << activity
        end

        expect(seen.first).to respond_to(:call)
      end
    end

    context "several items, jobs > 1 — not a terminal" do
      before { allow($stderr).to receive(:tty?).and_return(false) }

      it "runs every item and returns results in input order, not completion order" do
        delays = { a: 0.02, b: 0 }
        result = described_class.concurrently(%i[a b], "round", jobs: 2) { |item|
          sleep(delays[item])
          item
        }

        expect(result).to eq(%i[a b])
      end

      it "prints a header line and one completion line per item" do
        expect { described_class.concurrently(%i[a b], "round 1 — 2 plans", jobs: 2, label: ->(i) { i.to_s }) { |i| i } }
          .to output(a_string_including("round 1", "[✓] a", "[✓] b")).to_stderr
      end

      it "captures a failing item as its error rather than aborting the others" do
        result = described_class.concurrently(%i[a b], "round", jobs: 2) { |item|
          raise "boom" if item == :a

          :ok
        }

        aggregate_failures do
          expect(result[0]).to be_a(RuntimeError)
          expect(result[1]).to eq(:ok)
        end
      end
    end

    context "on a terminal" do
      before do
        allow(described_class).to receive(:tty?).and_return(true)
      end

      it "still returns every result for a single item" do
        expect(described_class.concurrently([:plan], "round", jobs: 1) { |_| :done }).to eq([:done])
      end
    end
  end

  # `Line#call` arrives several times a second from an agent's stream. The
  # line is redrawn every time, but the log takes a line only when the
  # phrase itself changes — otherwise an animated run writes nothing about
  # what any agent was doing, and a quiet run writes the same phrase hundreds
  # of times.
  describe "Line" do
    subject(:line) { described_class::Line.new(fields: { plan: "003.00" }, handle:) }

    let(:handle) { Dry::CLI::UI::Line.new }

    def progress(activity, up: 10, down: 2)
      OpenLanes::Execution::Transcript::Progress.new(activity:, up:, down:, subagents: 0)
    end

    around do |example|
      Dir.mktmpdir do |dir|
        @log_dir = dir
        example.run
      ensure
        described_class.log_path = nil
      end
    end

    # A `before`, not part of the `around`: the suite-wide `UI.reset!` hook
    # runs between the two and nils whatever log_path the around had set.
    before { described_class.log_path = File.join(@log_dir, "run.log") }

    it "redraws the meter and phrase on every update" do
      line.call(progress("reading spec.md"))

      expect(handle.detail).to include("↑10", "reading spec.md")
    end

    it "logs a phrase once, however many times the stream repeats it" do
      3.times { line.call(progress("reading spec.md")) }

      expect(File.read(described_class.log_path).scan("reading spec.md").size).to eq(1)
    end

    it "logs again when the agent moves on to something new" do
      line.call(progress("reading spec.md"))
      line.call(progress("editing plan.md"))

      log = File.read(described_class.log_path)
      aggregate_failures do
        expect(log).to include("reading spec.md")
        expect(log).to include("editing plan.md")
      end
    end

    # A usage-only delta carries token counts and no phrase. The meter must
    # still move, and the log must not fill with blank lines.
    it "updates the meter and skips the log when the update has no phrase" do
      line.call(progress(nil, up: 999))

      aggregate_failures do
        expect(handle.detail).to eq(described_class.meter(progress(nil, up: 999)).rstrip)
        expect(File.exist?(described_class.log_path)).to be(false)
      end
    end

    # Before the first number arrives the meter already reads zero, so the
    # phrase after it does not jump sideways when the count appears.
    it "starts with a zeroed meter" do
      line.start

      expect(handle.detail).to include("↑0", "↓0")
    end

    it "runs with no handle at all — a piped run still logs" do
      bare = described_class::Line.new(fields: { plan: "003.00" })
      bare.call(progress("reading spec.md"))

      expect(File.read(described_class.log_path)).to include("reading spec.md")
    end

    # Executor passes the line straight on as its stream callback.
    it "converts to a proc that behaves exactly like #call" do
      line.to_proc.call(progress("reading spec.md"))

      expect(handle.detail).to include("reading spec.md")
    end

    # The executor reports a timed-out agent by returning, not by raising.
    it "fails its handle without raising, reason and all" do
      line.failed("timed out after 900s")

      aggregate_failures do
        expect(handle).to be_failed
        expect(handle.reason).to eq("timed out after 900s")
      end
    end
  end

  # On a terminal the work is a spinner task list, with the same contract as
  # everywhere else: input order, one failure contained, at most `jobs` at once.
  describe ".concurrently on a terminal" do
    before { allow(described_class).to receive(:tty?).and_return(true) }

    context "with every item succeeding" do
      subject(:result) { described_class.concurrently(%i[a b], "round", jobs: 2) { |item, _line| item } }

      it "returns results in input order" do
        expect(result).to eq(%i[a b])
      end
    end

    context "with a failing item among several" do
      subject(:result) {
        described_class.concurrently(%i[a b], "round", jobs: 2) { |item, _line|
          raise "boom" if item == :a

          :ok
        }
      }

      it "keeps the failing item's error as its result" do
        expect(result[0]).to be_a(RuntimeError)
      end

      it "does not stop the others" do
        expect(result[1]).to eq(:ok)
      end
    end

    context "with a lone item that raises" do
      subject(:run) { -> { described_class.concurrently([:a], "round", jobs: 1) { |_, _| raise "boom" } } }

      it "lets the exception propagate" do
        expect(run).to raise_error("boom")
      end
    end

    context "with more items than jobs" do
      # Forced before the threads start, so no worker races to memoize them.
      let!(:lock) { Mutex.new }
      let!(:counts) { { running: 0, peak: 0 } }

      before do
        described_class.concurrently(%i[a b c d e], "round", jobs: 2) do |_item, _line|
          lock.synchronize { counts[:peak] = [counts[:peak], counts[:running] += 1].max }
          sleep(0.02)
          lock.synchronize { counts[:running] -= 1 }
        end
      end

      it "never runs more than `jobs` items at once" do
        expect(counts[:peak]).to eq(2)
      end
    end

    context "with each item's line collected" do
      let!(:seen) { [] }

      before { described_class.concurrently(%i[a b], "round", jobs: 2) { |_item, line| seen << line } }

      it "hands each item a line of its own" do
        expect(seen).to all(be_a(OpenLanes::UI::Line))
      end
    end
  end

  describe ".concurrently under --quiet on a terminal" do
    subject(:result) { described_class.concurrently(%i[a b], "round", jobs: 2) { |item, _line| item } }

    before do
      allow(described_class).to receive(:tty?).and_return(true)
      described_class.quiet = true
    end

    it "draws nothing" do
      expect { result }.not_to output.to_stderr
    end

    it "still returns every result" do
      expect(result).to eq(%i[a b])
    end
  end

  # Column alignment in a terminal is measured in cells, and a character is
  # not a cell. Every example here is a case where counting characters — what
  # `format("%-4s")` does — gets the width wrong.
  describe ".fit" do
    it "pads a plain string to the asked-for width" do
      expect(described_class.fit("ab", 5)).to eq("ab   ")
    end

    it "truncates a string wider than the column" do
      expect(described_class.fit("abcdef", 3)).to eq("abc")
    end

    # "✅" is a single character that occupies two cells, so `%-2s` would leave
    # it unpadded at two cells wide — right by luck — while `%-3s` would pad it
    # to four.
    it "counts a one-character wide emoji as the two cells it draws" do
      expect(described_class.fit("✅", 2)).to eq("✅")
    end

    # "⚪️" is a base character plus a variation selector: two characters, still
    # two cells.
    it "counts a two-character emoji as the two cells it draws" do
      expect(described_class.fit("⚪️", 2)).to eq("⚪️")
    end

    # And the case that motivated all of this: two characters, but only one
    # cell, so it needs a space to sit in the same column as its neighbours.
    it "pads an emoji that draws narrower than it is written" do
      expect(described_class.fit("🅱️", 2)).to eq("🅱️ ")
    end

    it "never returns something wider than the column it was given" do
      widths = OpenLanes::Plans::STATUSES.map { |s| described_class.display_width(described_class.fit(s.emoji, 2)) }

      expect(widths.uniq).to eq([2])
    end
  end

  describe ".labelled" do
    let(:rows) do
      [["Progress", "/tmp/openlanes-minesweeper.log"],
       ["Live board", ["redis://localhost:6379 as kig@host", "(c016ff29b4961a744912c240:734c0aa1d2e3)"]],
       ["Control room", "http://127.0.0.1:11000"]]
    end

    it "pads every label to the widest, so the values start in one column" do
      expect(described_class.labelled(rows, room: 100)).to eq(<<~TEXT.chomp)
        Progress:     /tmp/openlanes-minesweeper.log
        Live board:   redis://localhost:6379 as kig@host (c016ff29b4961a744912c240:734c0aa1d2e3)
        Control room: http://127.0.0.1:11000
      TEXT
    end

    it "puts a part that does not fit on a continuation line under the values" do
      expect(described_class.labelled(rows, room: 60).lines(chomp: true)[1, 2]).to eq(
        ["Live board:   redis://localhost:6379 as kig@host",
         "              (c016ff29b4961a744912c240:734c0aa1d2e3)"]
      )
    end

    it "breaks a path wider than its column between directories, each piece under the values" do
      text = described_class.labelled([["Progress", "/var/folders/jq/853fg3814rs6xx/T/openlanes-minesweeper.log"]], room: 41)

      expect(text.lines(chomp: true)).to eq(["Progress: /var/folders/jq/853fg3814rs6xx/",
                                             "          T/openlanes-minesweeper.log"])
    end

    it "cuts a name wider than the column anywhere, rather than overflow it" do
      text = described_class.labelled([["Id", "x" * 25]], room: 14)

      expect(text.lines(chomp: true)).to eq(["Id: #{"x" * 10}", "    #{"x" * 10}", "    #{"x" * 5}"])
    end

    it "fits inside the box dry-cli-ui draws" do
      allow(described_class).to receive(:tty?).and_return(false)
      expect(described_class.box_room).to eq([described_class.width, 78].min - 6)
    end
  end

  # A box that is one row short loses its last line, and the last line is where
  # the instruction is. One run reported ten agent failures as four this way.
  describe ".box" do
    let(:long) { "a" * (described_class.width + 40) }

    it "keeps the last line when an earlier one has to wrap" do
      expect { described_class.box(:warn, "#{long}\nrun `unset ANTHROPIC_API_KEY` first") }.to output(/unset ANTHROPIC_API_KEY/).to_stderr
    end

    # dry-cli-ui sends `info` and `success` to its `out`. Here STDOUT is the
    # deliverable, so a success box landing in it would end up in a pipe.
    it "draws every kind on STDERR, success included" do
      expect { described_class.box(:success, "linked 4 skills") }
        .to output(/Success.*linked 4 skills/m).to_stderr.and(not_to_output.to_stdout)
    end

    # `Kernel.warn` writes nothing under -W0, which CI images and agent
    # harnesses set. A box is the explanation of a failure; it must survive.
    it "still draws with warnings silenced" do
      verbose = $VERBOSE
      $VERBOSE = nil
      expect { described_class.box(:error, "401 API key is invalid") }.to output(/401 API key is invalid/).to_stderr
    ensure
      $VERBOSE = verbose
    end
  end

  describe ".line" do
    it "still prints with warnings silenced" do
      verbose = $VERBOSE
      $VERBOSE = nil
      expect { described_class.line("renamed 003.00") }.to output(/renamed 003\.00/).to_stderr
    ensure
      $VERBOSE = verbose
    end
  end

  describe ".display_width" do
    it "measures cells rather than characters" do
      aggregate_failures do
        expect(described_class.display_width("abc")).to eq(3)
        expect(described_class.display_width("✅")).to eq(2)
        expect(described_class.display_width("")).to eq(0)
      end
    end
  end
end

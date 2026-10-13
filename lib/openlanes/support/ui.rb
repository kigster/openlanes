# frozen_string_literal: true

require "concurrent/hash"
require "etc"
require "fileutils"
require "dry/cli/ui"
require "pastel"
require "stringio"
require "tty/screen"
require "unicode/display_width"

module OpenLanes
  # Everything the user sees that is not the deliverable itself.
  #
  # Include it and you get `info`, `warn`, `error` and `success` as instance
  # methods, each drawing a dry-cli-ui box on **STDERR**. STDERR is deliberate:
  # the documents and tables these commands produce own STDOUT, so every
  # command composes in a pipe.
  #
  # @example
  #   class Thing
  #     include OpenLanes::UI
  #     def run = success("Linked 4 skills")
  #   end
  module UI
    # Widest a box may be drawn, regardless of how wide the terminal is.
    MAX_WIDTH = 100

    # Narrowest, so a small terminal still produces readable boxes.
    MIN_WIDTH = 60

    # Below this many items a progress bar is noise: it appears and vanishes
    # before the eye resolves it, and the line it prints is longer than the work.
    PROGRESS_THRESHOLD = 3

    # What an item contributes to its log line's columns when its caller has
    # nothing to say about it. A round header is such an item, and it still
    # has to line up with the agent lines under it.
    NO_FIELDS = ->(_item) { {} }

    # What an item's countdown starts from when its caller has no opinion:
    # nothing, so no timer is drawn. A line without a deadline showing 0:00
    # forever would read as an agent perpetually out of time.
    NO_TIMEOUT = ->(_item) {}

    # The countdown turns red with this many seconds left — late enough to
    # stay calm through a normal run, early enough to look up before the
    # executor pulls the plug.
    TIMER_WARNING = 60

    # How a block's RETURN VALUE is judged when its caller has no opinion:
    # nothing is ever a failure. The distinction exists because {Runner}'s
    # executor reports failure by returning a not-ok result rather than by
    # raising — and a line that drew ✓ "done" over a timed-out agent, while
    # the round table under it said FAIL, was the contradiction this closes.
    NO_FAILURE = ->(_result) {}

    # Longest phrase a spinner line can carry without wrapping into the next.
    SAID_LIMIT = 56

    # One item's line on the screen, and the same news written to the log.
    #
    # These are two readers of one story and used to be told it separately:
    # the spinner got the phrase, the log got a start and a finish, and an
    # animated run wrote nothing about what any agent was actually doing. A
    # {OpenLanes::Execution::Transcript::Progress} arrives here several times a
    # second; the line is redrawn every time, and the log takes a line only
    # when the phrase itself changes, which is a few dozen times an agent.
    #
    # The drawing belongs to dry-cli-ui. This keeps the parts the text after
    # the agent's name is made of — identity, countdown, meter, phrase — and
    # hands the whole of it to the {Dry::CLI::UI::Line} whenever one changes.
    class Line
      # @param fields [Hash] plan, status and agent, for the log's columns
      # @param handle [Dry::CLI::UI::Line, nil] what dry-cli-ui draws this
      #   item's line from; nil where nothing is being drawn
      # @param timeout [Integer, nil] seconds until the executor abandons
      #   this agent; drawn as a countdown on the line, nil draws nothing
      def initialize(fields: {}, handle: nil, timeout: nil)
        @fields = fields
        @handle = handle
        @timeout = timeout
        @started = UI.monotonic
        @phrase = nil
        @pid = nil
        @ticker = nil
        # The meter starts at zero rather than appearing with the first
        # number, which would shift everything after it sideways.
        @parts = { pid: "", timer: "", meter: UI.meter(nil), activity: "" }
        @lock = Mutex.new
      end

      # @return [Float] seconds this agent has been alive
      def seconds = UI.monotonic - @started

      # @return [String] the same, as the log and the report write it
      def alive = "#{seconds.round}s"

      # @param message [String]
      # @return [void]
      def note(message) = UI.log(message, **@fields, seconds:)

      # @return [void]
      def start
        redraw(pid: identity)
        tick
        note("started")
      end

      # What remains on this agent's clock, or nil when it has none. Floored
      # at zero: the executor's kill and this thread's wake-up race by up to
      # a second, and a line reading `-0:01` accuses the wrong party.
      #
      # @return [Integer, nil]
      def remaining
        return nil unless @timeout

        [@timeout - seconds, 0].max.round
      end

      # The countdown, redrawn once a second on its own thread. Progress
      # updates cannot drive it — they arrive only while the agent is
      # talking, and a stalled agent is exactly when the clock matters most.
      #
      # @return [void]
      def tick
        return unless @handle && @timeout

        redraw(timer: UI.countdown(remaining))
        @ticker ||= Thread.new do
          loop do
            sleep(1)
            left = remaining
            redraw(timer: UI.countdown(left))
            break unless left.positive?
          end
        rescue StandardError
          # A dying line must not take the round down with it.
        end
      end

      # @return [void]
      def stop_ticker
        @ticker&.kill
        @ticker = nil
      end

      # What sits between the agent's name and its activity: the `claude`
      # process and the round, `[36123, round 01]`, so a line on the screen
      # can be matched to a process in `ps` and a row in the report. The pid
      # is unknowable until the child has been spawned and found, so it reads
      # `…` until then; a caller with neither fact gets nothing at all.
      #
      # @return [String]
      def identity
        round = @fields[:round]
        return "" if round.nil? && @pid.nil?

        inner = [(@pid || "…").to_s, ("round #{round}" if round)].compact.join(", ")
        UI.paint("[#{inner}]", :bright_black)
      end

      # What the line shows after the agent's name.
      #
      # @return [String] e.g. `[36123, round 01] 14:59 ↑4.9k ↓512: reading spec.md`
      def detail
        parts = @lock.synchronize { @parts.dup }
        [parts[:pid], parts[:timer] + parts[:meter]].map(&:rstrip).reject(&:empty?).join(" ") + parts[:activity]
      end

      # @return [void]
      def done
        stop_ticker
        note("finished after #{alive}")
      end

      # Ends the line as a failure without raising: the executor reports a
      # timed-out agent by returning, and the line must still say 𝘅.
      #
      # @param reason [String]
      # @return [void]
      def failed(reason)
        stop_ticker
        @handle&.fail(reason)
        note("failed after #{alive}: #{reason}")
      end

      # @param update [OpenLanes::Execution::Transcript::Progress]
      # @return [void]
      def call(update)
        if update.respond_to?(:pid) && update.pid && update.pid != @pid
          @pid = update.pid
          redraw(pid: identity)
          note("claude is pid #{@pid}")
        end
        redraw(meter: UI.meter(update), activity: UI.said(update.activity))
        return if update.activity.nil? || update.activity == @phrase

        @phrase = update.activity
        note(update.activity)
      end

      # So a caller can pass this straight on as a block: {Executor} yields
      # to it from the thread it reads the agent's stream on.
      #
      # @return [Proc]
      def to_proc = method(:call).to_proc

      private

      # Called from the reader thread and the ticker at once, which is why
      # the parts are replaced under a lock rather than assembled in place.
      #
      # @param parts [Hash{Symbol => String}]
      # @return [void]
      def redraw(**parts)
        @lock.synchronize { @parts.merge!(parts) }
        @handle&.detail = detail
      end
    end

    class << self
      # Set by the CLI's --quiet. Silences spinners and bars along with
      # everything else, so a quiet run really is quiet.
      #
      # @return [Boolean]
      attr_accessor :quiet

      # @return [Pastel] colour engine, disabled when STDERR is not a terminal
      def pastel = @pastel ||= Pastel.new(enabled: color?)

      # Forget everything memoized here.
      #
      # Pastel captures `enabled:` once, at construction. Anything that changes
      # the answer afterwards — a test stubbing `tty?`, a caller setting
      # NO_COLOR late — would otherwise be ignored for the rest of the process,
      # and the first answer would leak into every later call.
      #
      # @return [void]
      def reset!
        remove_instance_variable(:@pastel) if instance_variable_defined?(:@pastel)
        self.quiet = false
        self.log_path = nil
      end

      # Where {.log} appends to, if anywhere. nil (the default) means nowhere;
      # `openlanes run` sets this before the loop starts, so a round
      # started under a tool that discards STDERR — an agent's own Bash call,
      # for instance — still leaves something to `tail -f`.
      #
      # @return [String, nil]
      attr_accessor :log_path

      # Something else that hears every {.log} line, as it is logged: the
      # live board keeps the latest few for the page. Taps are called on the
      # logging thread and must not raise.
      #
      # @param tap [#call] receives the message and its fields
      # @return [#call] the tap, to hand back to {.untap_log}
      def tap_log(tap)
        @log_taps = [*log_taps, tap]
        tap
      end

      # @param tap [#call]
      # @return [void]
      def untap_log(tap)
        @log_taps = log_taps - [tap]
      end

      # @return [Array<#call>]
      def log_taps = @log_taps || []

      # Append one timestamped line to {.log_path}. A no-op with nothing set.
      # Safe to call from several threads at once.
      #
      # @param message [String]
      # @return [void]
      def log(message, **fields)
        log_taps.each { |tap| tap.call(message, fields) }
        path = log_path or return

        # Taps hear every field; the file takes only its own columns, so a
        # field meant for the terminal (the state a plan moved to) adds
        # nothing to the file's format.
        line = Engine::ProgressLog.render(message, **fields.slice(*Engine::ProgressLog::FIELDS))
        (@log_mutex ||= Mutex.new).synchronize do
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "a") { |f| f.puts(line) }
        end
      end

      # Cells the meter takes on a spinner line, per direction.
      #
      # Fixed, and padded to it, because the numbers grow as the agent works and
      # a column that sizes itself to them drags the whole line sideways every
      # few seconds.
      METER_WIDTH = 7

      # The token counter that sits between the spinner and the agent's name.
      #
      # Up is everything sent, cache reads included, which is most of it. Down
      # is what the model generated. Sub-agent spend is folded into up, since
      # `claude` reports a sub-agent's total without splitting it.
      #
      # @param update [OpenLanes::Execution::Transcript::Progress, nil]
      # @return [String]
      def meter(update)
        paint(fit("↑#{abbreviate(update&.up)}", METER_WIDTH), :bright_blue) +
          paint(fit("↓#{abbreviate(update&.down)}", METER_WIDTH), :bright_magenta)
      end

      # Cells the countdown takes, `MM:SS ` included — the run default of
      # 900s reads `15:00`, and padding to a fixed width keeps the columns
      # to its right from stepping sideways once `9:59` loses a digit.
      TIMER_WIDTH = 6

      # The countdown that sits between the spinner and the meter: what is
      # left of the agent's timeout, quiet grey until the last
      # {TIMER_WARNING} seconds, red from there down.
      #
      # @param left [Integer, nil] seconds remaining; nil draws nothing
      # @return [String]
      def countdown(left)
        return "" if left.nil?

        text = fit(format("%d:%02d", left / 60, left % 60), TIMER_WIDTH)
        paint(text, left <= TIMER_WARNING ? :red : :bright_black)
      end

      # Token counts run to seven figures, and seven figures on a spinner line
      # is four cells of noise about a number nobody reads to the digit.
      #
      # @param count [Integer]
      # @return [String] e.g. "512", "4.9k", "121k", "1.6M"
      def abbreviate(count)
        count = count.to_i
        case count
        when 0...1_000 then count.to_s
        when 1_000...10_000 then "#{(count / 1000.0).round(1)}k"
        when 10_000...1_000_000 then "#{(count / 1000.0).round}k"
        when 1_000_000...10_000_000 then "#{(count / 1_000_000.0).round(1)}M"
        else "#{(count / 1_000_000.0).round}M"
        end
      end

      # @param phrase [String, nil]
      # @return [String] the phrase as a spinner line carries it, cut to
      #   {SAID_LIMIT}
      def said(phrase)
        text = phrase.to_s
        return "" if text.empty?

        text = "#{text[0, SAID_LIMIT - 1]}…" if text.length > SAID_LIMIT
        paint(": #{text}", :green, :bold)
      end

      # @return [Boolean] whether STDERR is an interactive terminal
      def tty? = $stderr.tty?

      # Whether animated output is worth drawing at all. A pipe, a CI log or a
      # --quiet run gets none: spinner frames written to a file are line noise.
      #
      # @return [Boolean]
      def animate? = tty? && !quiet

      # Indeterminate work — one call whose duration cannot be predicted, such
      # as a network round trip. The spinner runs until the block returns.
      #
      # @param message [String] what is being waited on
      # @yieldparam activity [Proc] phrase -> void, for news about the work
      # @yieldreturn [Object] whatever the work produces
      # @return [Object] the block's value, untouched
      def spinning(message)
        return yield(logging_activity(message)) unless animate?

        console.spinner(message) { |line| yield(activity_for(line)) }
      end

      # Determinate work — N items of roughly equal cost. Yields each item and
      # advances the bar; returns the collection so it can be chained.
      #
      # @param items [Array]
      # @param message [String]
      # @yieldparam item [Object]
      # @return [Array] +items+
      def stepping(items, message, &)
        list = items.to_a
        return list.each(&) unless animate? && list.size >= PROGRESS_THRESHOLD

        console.progress(message, total: list.size) do |bar|
          list.each do |item|
            yield item
            bar.advance
          end
        end
        list
      end

      # The dry-cli-ui console every box, spinner and bar here draws through.
      #
      # Both of its streams are STDERR, because dry-cli-ui sends `info` and
      # `success` to its `out`, and STDOUT here belongs to the deliverable.
      # Colour and animation are decided once, by {.color?} and {.animate?},
      # rather than by the gem looking at the stream a second time and
      # possibly disagreeing about --quiet.
      #
      # Built on every call rather than memoized: `$stderr` is swapped out by
      # the specs and by `output(...).to_stderr`, and a console holding on to
      # the stream it was born with would write past every one of them.
      #
      # @return [Dry::CLI::UI::Console]
      def console
        Dry::CLI::UI::Console.new(out: $stderr, err: $stderr, color: color?, animate: animate?, box_width: width)
      end

      # Run a block over many items at once, one line each.
      #
      # This is the shape for work that is independent and slow: each item gets
      # its own line, its own thread and its own success or failure mark, so a
      # long round reads as progress rather than as a hang.
      #
      # Results come back in the order the items were given, not the order they
      # finished — a caller that had to re-sort them would be a caller that
      # eventually forgets to.
      #
      # Every path here — one item, several without a terminal, several with
      # one — reports something. `jobs <= 1 || list.size <= 1` used to bypass
      # all of it and run silently, which is exactly the shape a `--plan
      # NNN.MM` round takes: one plan, one agent, nothing printed until the
      # whole thing finished and it was too late to tell "working" from "hung."
      #
      # Several items are a dry-cli-ui task list, capped at `jobs` at once. A
      # failing item is caught inside its own task, so its line reads 𝘅 and
      # its siblings carry on.
      #
      # @param items [Array]
      # @param message [String] the header line
      # @param jobs [Integer] how many run at once
      # @param label [Proc] item -> the text on its line
      # @param failure [Proc] the block's return value -> a reason when that
      #   value reports a failure, nil when it reports success. The block
      #   returning normally is not the same fact as the work having worked.
      # @param header [Hash] log columns for the header line itself, so the
      #   line announcing a round carries the same round number as the agent
      #   lines under it rather than a blank cell
      # @yieldparam item [Object]
      # @yieldparam line [Line]
      # @return [Array] one result per item, in input order
      def concurrently(items, message, jobs:, label: :to_s.to_proc, fields: NO_FIELDS,
        failure: NO_FAILURE, header: {}, timeout: NO_TIMEOUT, &)
        list = items.to_a
        return [] if list.empty?

        log(message, **header)

        if jobs <= 1 || list.size <= 1
          report_line(message) unless animate?
          return list.map { |item| once(item, label, fields, failure:, timeout:, &) }
        end

        results = Concurrent::Hash.new
        progress.tasks(message, concurrent: jobs) do |tasks|
          list.each_with_index do |item, index|
            tasks.task(label.call(item)) do |handle|
              line = Line.new(fields: fields.call(item), handle:, timeout: timeout.call(item))
              results[index] = attempt(item, line, failure, &)
            rescue StandardError => e
              results[index] = e
            end
          end
        end
        list.each_index.map { |i| results[i] }
      end

      # The same news, with no spinner to put it on. A piped or CI run still
      # wants it, in the log where the rest of that run's progress goes.
      #
      # @param text [String] the item's label
      # @return [Proc] phrase -> void
      def logging_activity(text) = ->(phrase) { log("#{text}: #{phrase}") }

      # A callable that writes what the work is doing after its spinner's label.
      #
      # @param line [Dry::CLI::UI::Line]
      # @return [Proc] phrase -> void
      def activity_for(line)
        ->(phrase) { line.detail = phrase.to_s.empty? ? "" : paint("— #{phrase}", :green, :bold) }
      end

      # One item, no concurrency to speak of: a serial round (`--isolation
      # shared`), or the last plan left in a parallel one. A live spinner on a
      # terminal; a start line and a finish line with an elapsed time otherwise.
      #
      # @param item [Object]
      # @param label [Proc]
      # @yieldparam item [Object]
      # @return [Object]
      # @raise [StandardError] whatever the block raised, once its line says so
      def once(item, label, fields = NO_FIELDS, failure: NO_FAILURE, timeout: NO_TIMEOUT, &)
        progress.spinner(label.call(item)) do |handle|
          attempt(item, Line.new(fields: fields.call(item), handle:, timeout: timeout.call(item)), failure, &)
        end
      end

      # Runs one item and says how it went, on its line and in the log.
      #
      # @param item [Object]
      # @param line [Line]
      # @param failure [Proc]
      # @return [Object] the block's value
      def attempt(item, line, failure)
        line.start
        begin
          result = yield(item, line)
        rescue StandardError => e
          line.failed(e.message.lines.first.to_s.strip)
          raise
        end
        if (reason = failure.call(result))
          line.failed(reason)
        else
          line.done
        end
        result
      end

      # The console per-item lines go through: {.console}, or one that
      # writes nowhere under --quiet, so a quiet run really is quiet while
      # the work, the log and the results stay exactly the same.
      #
      # @return [Dry::CLI::UI::Console]
      def progress
        return console unless quiet

        Dry::CLI::UI::Console.new(out: StringIO.new, err: StringIO.new, color: false, animate: false)
      end

      # @return [Float] a monotonic clock reading, immune to wall-clock changes
      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # @param started [Float] a {#monotonic} reading taken before the work began
      # @return [String] e.g. "42s"
      def elapsed(started) = "#{(monotonic - started).round}s"

      # A progress line, thread-safe and quiet-aware — the one thing every
      # non-spinner path above needs and would otherwise have to reimplement.
      #
      # @param text [String]
      # @param bullet [String]
      # @return [void]
      def report_line(text, bullet: "·")
        return if quiet

        (@print_mutex ||= Mutex.new).synchronize { line(text, bullet:) }
      end

      # A sensible worker count: agents are mostly waiting on a model rather
      # than burning CPU, so this is deliberately close to the core count. Two
      # are left for the machine, and the cap keeps a very large tree from
      # opening fifty subprocesses at once.
      #
      # @return [Integer]
      def default_jobs = (Etc.nprocessors - 2).clamp(1, 12)

      # Honours NO_COLOR — https://no-color.org
      #
      # @return [Boolean]
      def color? = tty? && !ENV.key?("NO_COLOR")

      # @return [Integer] a box width that fits the terminal but stays readable
      def width = (TTY::Screen.width - 4).clamp(MIN_WIDTH, MAX_WIDTH)

      # @param text [String]
      # @param styles [Array<Symbol>] pastel style names
      # @return [String] decorated when colour is on, bare otherwise
      def paint(text, *styles) = color? ? pastel.decorate(text.to_s, *styles) : text.to_s

      # @param text [String]
      # @return [Integer] how many terminal cells the text occupies
      def display_width(text) = ::Unicode::DisplayWidth.of(text.to_s)

      # Pad or truncate to an exact number of terminal *cells*.
      #
      # `format`'s "%-20.20s" counts characters, and a character is not a cell.
      # "✅" is one character two cells wide; "🅱️" is two characters one cell
      # wide. Any column laid out with %s therefore drifts by one for every
      # emoji whose two counts disagree — which is every emoji, in one
      # direction or the other.
      #
      # @param text [String] unpainted; escape codes count as characters and
      #   would be padded like any other
      # @param width [Integer] terminal cells
      # @return [String]
      def fit(text, width)
        text = text.to_s
        text = text[0..-2] while display_width(text) > width
        text + (" " * (width - display_width(text)))
      end

      # Every box is drawn by dry-cli-ui, on STDERR, through {.console}.
      #
      # Not through `Kernel.warn`, which is a **no-op** when `$VERBOSE` is
      # nil, which is what `-W0` sets — and `RUBYOPT=-W0` is common in CI
      # images and agent harnesses. Routed through `Kernel.warn`, every box
      # this tool draws silently disappears in exactly the environments where
      # a failure most needs explaining. The console writes to its stream.
      #
      # dry-cli-ui wraps before it frames, so a long line no longer costs the
      # box its last row, which is where the instruction lives. One run
      # reported four of its ten failures and cut the fifth mid-sentence.
      #
      # @param kind [Symbol] :info, :warn, :error or :success
      # @param message [String]
      # @return [void]
      def box(kind, message) = console.public_send(kind, message.to_s)

      # A framed panel centered on the screen, for the keyboard help. Unlike
      # {.box} it positions itself absolutely, so it overlays whatever the
      # spinners are drawing rather than scrolling in below them — the next
      # repaint draws over it, which is all the dismissal a help screen needs.
      #
      # @param title [String]
      # @param text [String]
      # @return [void]
      def popup(title, text) = console.popup(text.to_s, title:)

      # A framed table, returned rather than printed: a table is a
      # deliverable, so it belongs on STDOUT and the caller picks the stream.
      #
      # @param rows [Array<Array<#to_s>>]
      # @param header [Array<#to_s>, nil]
      # @return [String] the table ending in a newline, or "" when there are no rows
      def table(rows, header: nil)
        Dry::CLI::UI::Widgets::Table.new(Dry::CLI::UI::Terminal.new($stdout, color: color?)).render(rows, header:)
      end

      # A single unadorned line, for per-item progress that does not deserve
      # a box of its own.
      #
      # @param message [String]
      # @param bullet [String]
      # @return [void]
      # rubocop:disable-next Style/StderrPuts -- see {.box}: `warn` is a no-op under -W0.
      def line(message, bullet: "·") = $stderr.puts("  #{paint(bullet, :bright_black)} #{message}")
    end

    # @param message [String]
    # @return [void]
    def info(message) = UI.box(:info, message)

    # @param message [String]
    # @return [void]
    def warn(message) = UI.box(:warn, message)

    # @param message [String]
    # @return [void]
    def error(message) = UI.box(:error, message)

    # @param message [String]
    # @return [void]
    def success(message) = UI.box(:success, message)

    # @param message [String]
    # @param bullet [String]
    # @return [void]
    def say(message, bullet: "·") = UI.line(message, bullet:)

    # @param text [String]
    # @param styles [Array<Symbol>]
    # @return [String]
    def paint(text, *styles) = UI.paint(text, *styles)
  end
end

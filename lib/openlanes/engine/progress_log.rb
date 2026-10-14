# frozen_string_literal: true

module OpenLanes
  module Engine
    # One line of `run --log FILE`, laid out as fixed-width columns.
    #
    # The log file is the only record of a headless run, and it is shared: two
    # `openlanes run` invocations pointed at the same `--log` both append to
    # it, interleaved, and so does every round within one run. That is what the
    # process id column is for. Without it a reader cannot tell one run's agents
    # from another's, and "started 003.00" twice looks like a bug rather than two
    # machines doing the same work.
    #
    # Fixed columns are what make the file readable by eye and by `awk` alike. A
    # value wider than its column is cut rather than allowed to push the columns
    # out, and a value that is missing still occupies its width, so a round header
    # with no plan or agent of its own lines up with the lines underneath it.
    #
    # @example
    #   ProgressLog.render("editing spec.md", plan: "003.00", status: "⭐️ Planned",
    #     agent: "yoda-writer", seconds: 42, round: "01", pid: 91_234)
    #   #=> "[16:22:14 | 003.00 | ⭐️  Planned            | yoda-writer          | 01 |   91234 |    42s] editing spec.md"
    module ProgressLog
      # Wall clock only. A log line answers "when", and the date is the file's.
      TIME_FORMAT = "%H:%M:%S"

      # Width of {TIME_FORMAT}'s output.
      TIME_WIDTH = 8

      # "003.00".
      PLAN_WIDTH = 6

      # Cells given to the emoji, and the gap after it. Many terminal fonts draw
      # a colour emoji wider than its two cells, and with one space it overlapped
      # the label's first letter ("🔴Changes").
      EMOJI_WIDTH = 2
      EMOJI_GAP = "  "

      # Derived from the widest state as {.status_cell} renders it, so a state
      # added to {STATUSES} with a longer label cannot silently knock the columns
      # after it out of line. Untrimmed: cut to fit, "Changes Requested" and
      # "Ready for Planning" read as "Changes Reque" and "Ready for Pla".
      STATUS_WIDTH = Plans::STATUSES.map { |status| EMOJI_WIDTH + EMOJI_GAP.length + UI.display_width(status.label) }.max

      # The longest specialist name in `agents/` is `palpatine-planner` at 17,
      # and the names are hyphenated words rather than a bounded vocabulary, so
      # this leaves room for one more without a reflow.
      AGENT_WIDTH = 20

      # Enough for a 32-bit process id, right justified.
      PID_WIDTH = 7

      # "01". Rounds cap at two digits; a run that reaches a third has bigger
      # problems than this column.
      ROUND_WIDTH = 2

      # "  907s". Anything longer than four digits of seconds is an agent nobody
      # is still waiting on.
      SECONDS_WIDTH = 6

      # The keywords {.render} takes besides the message. {UI.log} hands its
      # taps more than these, and the file only these.
      FIELDS = %i[plan status agent seconds round pid at].freeze

      # Between columns, inside the brackets.
      SEPARATOR = " | "

      # Cells from the opening bracket to the closing one, separators included.
      # The message starts one space after this on every line, whatever fields
      # that line happens to be missing, so a reader indenting a wrapped message
      # has a number to indent by.
      COLUMN_WIDTHS = [TIME_WIDTH, PLAN_WIDTH, STATUS_WIDTH, AGENT_WIDTH, ROUND_WIDTH, PID_WIDTH,
                       SECONDS_WIDTH].freeze

      # @see COLUMN_WIDTHS
      LINE_WIDTH = COLUMN_WIDTHS.sum + (SEPARATOR.length * (COLUMN_WIDTHS.size - 1)) + 2

      class << self
        # Render one log line: bracketed fixed-width columns, then the message.
        #
        # No colour. The line goes to a file, where an escape sequence is neither
        # readable nor the width it claims to be.
        #
        # @param message [String] the free-form tail, the only variable-width part
        # @param plan [String, nil] the plan's ordinal, e.g. "003.00"
        # @param status [String, nil] emoji and label, e.g. "⭐️ Planned"
        # @param agent [String, nil] the specialist's name, e.g. "yoda-writer"
        # @param seconds [Numeric, nil] how long this agent has been alive
        # @param round [String, nil] which pass over the tree, e.g. "01"
        # @param pid [Integer, nil] which run wrote the line
        # @param at [Time] injectable, so a caller can render a fixed clock
        # @return [String] one line, with no trailing newline
        def render(message, plan: nil, status: nil, agent: nil, seconds: nil,
          round: nil, pid: Process.pid, at: Time.now)
          columns = [
            left(at.strftime(TIME_FORMAT), TIME_WIDTH),
            left(plan, PLAN_WIDTH),
            left(status_cell(status), STATUS_WIDTH),
            left(agent, AGENT_WIDTH),
            right(round, ROUND_WIDTH),
            right(pid, PID_WIDTH),
            right(duration(seconds), SECONDS_WIDTH)
          ]

          text = message.to_s
          prefix = "[#{columns.join(SEPARATOR)}]"
          text.empty? ? prefix : "#{prefix} #{text}"
        end

        # The emoji fitted to {EMOJI_WIDTH} and followed by {EMOJI_GAP}, then the
        # label. A value with no label (or none at all) passes through.
        #
        # @param status [String, nil] emoji and label, e.g. "⭐️ Planned"
        # @return [String, nil]
        def status_cell(status)
          emoji, label = status.to_s.split(" ", 2)
          return status if label.nil?

          "#{UI.fit(emoji, EMOJI_WIDTH)}#{EMOJI_GAP}#{label}"
        end

        # @param seconds [Numeric, nil]
        # @return [String] whole seconds with a trailing "s", or blank for nil
        def duration(seconds) = seconds.nil? ? "" : "#{seconds.round}s"

        # @param value [Object, nil]
        # @param width [Integer] terminal cells
        # @return [String] padded on the right to exactly +width+ cells
        def left(value, width) = UI.fit(value, width)

        # {UI.fit} pads on the right, which is the wrong end for a number. Fit
        # first so an over-long value is still truncated to the column, then move
        # the padding to the front.
        #
        # @param value [Object, nil]
        # @param width [Integer] terminal cells
        # @return [String] padded on the left to exactly +width+ cells
        def right(value, width)
          text = UI.fit(value, width).rstrip
          UI.fit("", width - UI.display_width(text)) + text
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    # What a run says on the terminal while it works: one plain line per
    # event, appended, never redrawn.
    #
    # It is a {UI.tap_log} tap, so it hears exactly what the progress log
    # file hears (an agent started or finished, a plan changed state, a
    # command came from the page, the reason the engine idles) and nothing
    # else. The file keeps its fixed columns for `awk`; the terminal gets
    # only the fields a line actually has. Echoing the file's format there
    # is what drew an idle line as a row of empty columns,
    # `[13:39:10 |        |  …  |   83054 |       ] idle: …`.
    #
    # Nothing here moves the cursor or colours anything. A line is written
    # whole, under a lock, with any carriage return or escape sequence in any
    # field (an agent's note is free text, a page command's plan is unchecked)
    # taken out first, so two threads logging at once
    # cannot splice their lines, and no message can rewrite the one above.
    # The same lines serve a terminal, a pipe and a CI log alike.
    #
    # @example
    #   narrator = Narrator.new
    #   UI.tap_log(narrator)
    #   UI.log("started", plan: "003.00", status: "⭐ Planned", agent: "spec-writer", round: "01")
    #   # 13:39:10  003.00 ⭐  Planned  spec-writer r01  started
    class Narrator
      # Between the parts of a line. Two spaces read as columns without
      # holding open the ones a line does not have.
      GAP = "  "

      # A carriage return, an escape sequence, or any other control
      # character but a tab: what would let one message overwrite another.
      CONTROL = %r{\e\[[0-9;?]*[ -/]*[@-~]|[\x00-\x08\x0a-\x1f\x7f]}

      # @param stream [#puts, nil] where the lines go; nil means whatever
      #   `$stderr` is when a line is written, so a spec swapping it is heard
      # @param clock [Proc] wall time, injectable for a fixed timestamp
      def initialize(stream: nil, clock: -> { Clock::System.now })
        @stream = stream
        @clock = clock
        @lock = Mutex.new
        @last = nil
      end

      # The tap itself. A line identical to the previous one is dropped, so
      # whatever repeats itself tick after tick (an idle reason, a store
      # that keeps refusing) is said once per change rather than once a
      # second.
      #
      # @param message [String]
      # @param fields [Hash] the log line's fields: plan, status, agent, round,
      #   and `to:` when the event moved the plan
      # @return [void]
      def call(message, fields = {})
        text = render(message, **fields)
        @lock.synchronize do
          next if text == @last

          @last = text
          # Unpainted, so a terminal gets the same bytes as a pipe or a CI log.
          (@stream || $stderr).puts("#{@clock.call.strftime(ProgressLog::TIME_FORMAT)}#{GAP}#{text}")
        end
      rescue StandardError
        # A tap runs on the logging thread and must never take it down;
        # a terminal that went away is no reason to stop the agents.
        nil
      end

      # @return [Proc] for {UI.tap_log}
      def to_proc = method(:call).to_proc

      # One event, without its timestamp.
      #
      # @param message [String]
      # @param plan [String, nil]
      # @param status [String, nil] emoji and label
      # @param agent [String, nil]
      # @param round [String, nil] e.g. "01"
      # @param to [String, nil] the state the plan moved to, emoji and label
      # @return [String] e.g. `003.00 ⭐  Planned  spec-writer r01  finished → 🟡  Building`
      def render(message, plan: nil, status: nil, agent: nil, round: nil, to: nil, **)
        # Every field, not just the message: a page command's plan and agent
        # are logged before anything checks that they name real ones.
        plan, status, agent, round = [plan, status, agent, round].map { clean(it) if it }
        said = clean(message)
        said = "#{said} → #{self.class.status_cell(clean(to))}" if to
        [[plan, (self.class.status_cell(status) if status)].compact.join(" "), [agent, ("r#{round}" if round)].compact.join(" "), said]
          .reject(&:empty?).join(GAP)
      end

      # The emoji fitted to two cells and followed by two spaces, then the
      # label, exactly as the progress log draws it.
      #
      # @param status [String] emoji and label, e.g. "⭐ Planned"
      # @return [String] e.g. "⭐  Planned"
      def self.status_cell(status) = ProgressLog.status_cell(status).to_s

      private

      # @param text [Object]
      # @return [String] on one line, with nothing that moves the cursor
      def clean(text) = text.to_s.gsub(CONTROL, " ").squeeze(" ").strip
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    # What the screen draws: everything about the run, as values, refreshed
    # once a second by the dispatcher. The screen paints it and knows nothing
    # about threads; the dispatcher builds it and knows nothing about cells.
    #
    # @!attribute [r] rows
    #   @return [Array<OpenLanes::Engine::Board::Row>] one per agent invocation still
    #     worth showing: running, or finished within the last few seconds
    # @!attribute [r] waiting_on
    #   @return [Hash{String => Array<Integer>}] plan to the pull requests open
    #     and waiting on a person, as the human-mode watch last saw them (M4)
    Board = Data.define(:started_at,
      :status,
      :plans,
      :up,
      :down,
      :rows,
      :root,
      :running,
      :live_up,
      :live_down,
      :selected,
      :dialog,
      :help,
      :about,
      :hidden,
      :waiting_on) do
      def initialize(selected: nil, dialog: nil, help: false, about: nil, hidden: 0, waiting_on: {}, **rest) = super
    end

    # @!attribute [r] key
    #   @return [String] `"001.00/leah-researcher"`, what a command addresses a row by
    # @!attribute [r] file
    #   @return [String] the document holding the agent's latest ledger line
    # @!attribute [r] pr
    #   @return [Hash, nil] `{number:, url:, rejected:}` once the plan is at
    #     the review stage
    # @!attribute [r] state
    #   @return [Symbol] :running, :done, :failed or :stuck
    # @!attribute [r] phase
    #   @return [Symbol, nil] the clock's phase while running
    # @!attribute [r] frame
    #   @return [Integer] spinner frame counter
    # @!attribute [r] history
    #   @return [Array<String>] what the agent has said, newest first, for
    #     `run --scroll-height` to show more than the latest line of
    # @!attribute [r] context
    #   @return [Integer, nil] tokens in the agent's context, when its
    #     adapter's stream says
    # @!attribute [r] since
    #   @return [Float, nil] the monotonic time its invocation started, which
    #     tells two invocations of one round apart
    # @!attribute [r] session
    #   @return [String, nil] the CLI's session id, once its stream named it;
    #     what a compaction resumes (W28)
    # @!attribute [r] unacked
    #   @return [Integer] messages in the plan's mailbox nobody has acked yet.
    #     Data for the screen only (D2): no round, route or rename reads it,
    #     because an unanswered message is a warning, never an input.
    Board::Row = Data.define(:key,
      :at,
      :ordinal,
      :file,
      :agent,
      :role,
      :round,
      :rounds,
      :model,
      :remaining,
      :phase,
      :up,
      :down,
      :message,
      :state,
      :pr,
      :frame,
      :bold,
      :elapsed,
      :subagents,
      :history,
      :context,
      :since,
      :session,
      :unacked) do
      def initialize(pr: nil, phase: nil, remaining: nil, frame: 0, bold: false, message: nil,
        elapsed: 0, subagents: 0, history: [], context: nil, since: nil, session: nil, unacked: 0, **rest)
        super
      end

      # The count a row carries, read from the plan folder's mailbox, so the
      # dispatcher fills the field in one call and the snapshot and the board
      # cannot count differently (both ask Mailbox#unacked).
      #
      # @param dir [String] the plan folder
      # @return [Integer] 0 for a plan nobody has written to, and for one
      #   whose `state.json` cannot be read: a count for the screen must not
      #   stop the tick that draws it
      def self.unacked_in(dir)
        Plans.mailbox(dir).unacked
      rescue OpenLanes::Error, SystemCallError
        0
      end

      # @param history [Array<String>] newest first
      # @param text [String, nil]
      # @return [Array<String>] +text+ on top, unless it is empty or repeats
      #   the newest line: an agent restating its activity is not news
      def self.remember(history, text)
        text = text.to_s.strip
        return history if text.empty? || history.first == text

        [text, *history].first(Board::Row::HISTORY)
      end

      # @return [Boolean]
      def running? = state == :running
    end

    # Statuses a row keeps, whatever the screen shows of them. A cap, so a
    # long-running agent's chatter cannot grow without bound. Outside the
    # `Data.define` block, whose constants would land on OpenLanes instead.
    Board::Row::HISTORY = 50
  end
end

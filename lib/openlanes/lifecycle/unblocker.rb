# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # Draining a plan's `blocked.md`, and saying what happened.
    #
    # `unblock` is the one command a human runs *because* they know something the
    # tool cannot observe: an answer has arrived. So it owes them an account of
    # what it did with it. Four things can happen to a plan named on the command
    # line, and only one of them is the interesting one:
    #
    #   * the number names no folder,
    #   * the folder is not blocked and there is nothing to drain,
    #   * the folder is blocked, and some, none or all of its questions fold in,
    #   * `blocked.md` is there but numbers nothing `## B<n>`, so no program can
    #     read it at all.
    #
    # Each is reported differently, because each needs a different thing done
    # next. This object works out which one happened; {CLI::Unblock} prints it.
    class Unblocker
      # One open question, as `blocked.md` writes it.
      #
      # @!attribute [r] number
      #   @return [Integer] the `n` in `## B<n>`
      # @!attribute [r] heading
      #   @return [String] the heading text, hashes stripped
      # @!attribute [r] answered
      #   @return [Boolean] whether an `## A<n>` of the same number is waiting
      Question = Data.define(:number, :heading, :answered) do
        # @return [String]
        def to_s = answered ? "#{heading}  ← answer waiting" : heading
      end

      # One token from the command line, once the tree has had a look at it.
      #
      # @!attribute [r] token
      #   @return [String] what the user typed
      # @!attribute [r] subject
      #   @return [OpenLanes::Plans::Subject, nil]
      # @!attribute [r] problem
      #   @return [Symbol, nil] :missing, :not_blocked, or nil when it is drainable
      Target = Data.define(:token, :subject, :problem) do
        # @return [Boolean]
        def drainable? = problem.nil?
      end

      # What became of one plan.
      #
      # @!attribute [r] subject
      #   @return [OpenLanes::Plans::Subject] as the folder stands *now*
      # @!attribute [r] ok
      #   @return [Boolean] whether the agent ran without failing
      # @!attribute [r] note
      #   @return [String] one line about how it went
      # @!attribute [r] before
      #   @return [Array<Question>] open before the agent ran
      # @!attribute [r] after
      #   @return [Array<Question>] open now
      Outcome = Data.define(:subject, :ok, :note, :before, :after) do
        # @return [OpenLanes::Plans::Ordinal]
        def ordinal = subject.feature.ordinal

        # @return [Array<Integer>] the questions this run actually disposed of
        def folded = before.map(&:number) - after.map(&:number)

        # @return [Boolean] `blocked.md` is gone, so the plan is out of the block
        def cleared? = !subject.file?("blocked.md")

        # @return [Boolean] a `blocked.md` no program can read
        def unreadable? = subject.unreadable_block?

        # @return [Array<Question>] still open, with an answer sitting unfolded
        def waiting = after.select(&:answered)
      end

      # The questions a folder still names, in the order the file names them.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<Question>]
      def self.questions(subject)
        answered = subject.block_answers

        subject.read("blocked.md").to_s.lines.grep(Plans::OPEN_BLOCK).map do |line|
          number = line[Plans::OPEN_BLOCK, 1].to_i
          Question.new(number:, heading: line.strip.sub(/\A\#+[ \t]*/, ""), answered: answered.include?(number))
        end
      end

      # @param tree [OpenLanes::Plans::Tree]
      # @param agent [OpenLanes::Agents::Agent]
      # @param executor [#call] receives (agent, subject, root:) and yields each
      #   phrase describing what the agent is doing
      # @param root [String] the repository the agent works in
      # @param commit [Boolean] false plans the invocation and changes nothing
      def initialize(tree:, agent:, executor:, root: nil, commit: false)
        @tree = tree
        @agent = agent
        @executor = executor
        @root = root || File.dirname(tree.dir)
        @commit = commit
      end

      # @return [OpenLanes::Plans::Tree]
      attr_reader :tree

      # @return [OpenLanes::Agents::Agent]
      attr_reader :agent

      # @return [String]
      attr_reader :root

      # @return [Boolean]
      def applying? = @commit

      # Work out what each number on the command line refers to.
      #
      # Nothing is rejected here and nothing exits: a token that names no folder
      # is as much a thing the user needs told about as a folder that drained, and
      # stopping at the first bad one hides the rest of the report.
      #
      # The gate is `blocked.md` itself, not the folder's emoji. ⭕ is *derived*
      # from the file, so gating on the emoji made the tool circular: a
      # `blocked.md` whose questions are not numbered `## B<n>` never earns the
      # emoji, so `unblock` refused it, so the file could never drain and the
      # folder could never leave 🟡.
      #
      # @param tokens [Array<String>] `NNN`, `NNN.MM`, or several comma separated
      # @return [Array<Target>]
      def resolve(tokens)
        tokens.flat_map { |token| token.to_s.split(",") }.map(&:strip).reject(&:empty?).map do |token|
          subject = tree.find(token)
          next Target.new(token:, subject: nil, problem: :missing) if subject.nil?
          next Target.new(token:, subject:, problem: :not_blocked) unless subject.file?("blocked.md")

          Target.new(token:, subject:, problem: nil)
        end
      end

      # Hand each folder to the agent, one at a time, and read the file back.
      #
      # What the agent claims it did is not evidence. The questions are counted
      # off disk before and after, so "folded B3" means the heading is gone from
      # `blocked.md`, not that an agent said so.
      #
      # @param subjects [Array<OpenLanes::Plans::Subject>]
      # @return [Array<Outcome>]
      def call(subjects)
        return [] if subjects.empty?

        before = subjects.map { |subject| [subject.feature.ordinal.to_s, self.class.questions(subject)] }.to_h
        results = UI.concurrently(subjects,
          headline(subjects),
          jobs:   1,
          label:  method(:label),
          fields: method(:log_fields)) do |subject, progress|
          # After ctrl-c the plans not yet started stay as they are, blocked.md
          # untouched, so the next run picks them up from the beginning.
          next [false, "not started: interrupted by ctrl-c"] if Execution::Control.interrupted?

          invoke(subject, progress)
        end

        settle
        subjects.zip(results).map { |subject, result| outcome(subject, result, before) }
      end

      # One folder, with no spinner and no rename: what the run loop does when
      # a person has answered every question a blocked plan asked (plan 004).
      # The loop owns the screen, so nothing here draws on it, and the loop
      # owns renames, so the folder's name is left to its next `resync dirs`,
      # which sees `blocked.md` gone. Everything else is {#call}'s: the same
      # agent, the same invocation, the same count of questions off disk.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @yieldparam progress [Object] whatever the executor reports
      # @return [Outcome]
      def drain(subject, &progress)
        before = { subject.feature.ordinal.to_s => self.class.questions(subject) }
        result = applying? ? invoke(subject, progress || proc {}) : [false, "not attempted: a dry run"]
        tree.reload
        outcome(subject, result, before)
      end

      private

      # @param subject [OpenLanes::Plans::Subject]
      # @param progress [OpenLanes::UI::Line]
      # @return [Array(Boolean, String)]
      def invoke(subject, progress)
        @executor.call(agent, subject, root:, &progress)
      rescue StandardError => e
        [false, "#{e.class}: #{e.message.lines.first.to_s.strip}"]
      end

      # The same pass the run loop makes after every round, for the same reason:
      # a drained folder is only *named* differently once something reads the
      # file the agent just deleted.
      #
      # @return [void]
      def settle
        Resync::Dirs.new(tree:).call(commit: true) if applying?
        tree.reload
      end

      # @param subject [OpenLanes::Plans::Subject] as it was before the run
      # @param result [Array, Exception]
      # @param before [Hash{String => Array<Question>}]
      # @return [Outcome]
      def outcome(subject, result, before)
        ok, note = result.is_a?(Exception) ? [false, result.message.lines.first.to_s.strip] : result
        current = tree.find(subject.feature.ordinal) || subject

        Outcome.new(subject: current,
          ok: !!ok,
          note: note.to_s,
          before: before.fetch(subject.feature.ordinal.to_s, []),
          after: self.class.questions(current))
      end

      # @param subjects [Array<OpenLanes::Plans::Subject>]
      # @return [String]
      def headline(subjects)
        "#{applying? ? "handing" : "would hand"} #{subjects.size} plan#{"s" unless subjects.size == 1} " \
          "to #{agent.name} in #{root}"
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def label(subject) = "#{subject.feature.ordinal} → #{agent.name}"

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Hash] the columns this plan's log lines carry
      def log_fields(subject) = { plan: subject.feature.ordinal.to_s, status: subject.status.to_s, agent: agent.name }
    end
  end
end

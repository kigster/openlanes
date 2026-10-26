# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # `openlanes unblock NNN…` without the command: resolve the plans named,
    # refuse the ones that cannot be drained, say what each is waiting on,
    # hand the rest to the draining agent, and report what moved.
    #
    # Deliberately not part of `run`. ⭕ and 🛑 are {Plans::StateMachine::SETTLED},
    # so the loop never offers a blocked plan to anybody, and that is the
    # property that makes the state mean anything: the plan waits for a human,
    # and no agent quietly decides otherwise. Answers arriving is not a fact
    # the tool can observe, so a human typing the command *is* the signal.
    class UnblockWorkflow
      include UI
      include Dry::Monads[:result]

      # The agent that knows the shape of `blocked.md`.
      DEFAULT_AGENT = Agents::Names::UNBLOCKER

      # What each token turned out to be, for whoever has to fix it.
      PROBLEMS = {
        missing:     "no plan of that number",
        not_blocked: "no blocked.md, so there is nothing to drain"
      }.freeze

      # @param tree [OpenLanes::Plans::Tree]
      # @param agent [String] the name of the agent that drains
      # @param root [String, nil] repository root (default: the .plans parent)
      # @param dry_run [Boolean] invoke no agent, change nothing
      # @param quiet [Boolean] draw nothing on STDERR
      def initialize(tree:, agent: DEFAULT_AGENT, root: nil, dry_run: false, quiet: false)
        @tree = tree
        @agent = agent
        @root = root
        @dry_run = dry_run
        @quiet = quiet
      end

      # The deliverable rows go to STDOUT and the progress to STDERR as the
      # work happens; the answer is the exit status the command ends with.
      #
      # @param tokens [Array<String>] the plans named: NNN or NNN.MM
      # @return [Dry::Monads::Result] Success(Integer) the exit status, or
      #   Failure({Refusal}) when no agent has the name given
      def call(tokens)
        agent = OpenLanes::Agents.registry.find(@agent) or return Failure(unknown_agent)

        unblocker = Lifecycle.unblocker(tree: @tree,
          agent:,
          root: @root,
          commit: !@dry_run,
          executor: Execution.executor(root: @root || File.dirname(@tree.dir), dry_run: @dry_run))
        targets = unblocker.resolve(tokens)
        refused(targets)
        subjects = targets.select(&:drainable?).map(&:subject)
        return Success(worst(targets, [])) if subjects.empty?

        credentials unless @dry_run || @quiet
        preflight(subjects)

        outcomes = Execution.on_interrupt { unblocker.call(subjects) }
        outcomes.each { |outcome| report(outcome) }
        footer(outcomes) unless @quiet
        Success(worst(targets, outcomes))
      end

      private

      # @return [OpenLanes::Refusal]
      def unknown_agent
        known = OpenLanes::Agents.registry.all.map(&:name).join(", ")
        Refusal.new(message: "No agent called #{@agent}.\n\nKnown: #{known}", status: 65)
      end

      # @return [void]
      def credentials
        notice = Execution.credentials_notice
        warn(notice) if notice
      end

      # A number that names no folder, or a folder that was never stopped, is
      # refused rather than skipped. Whoever typed this believes an answer has
      # arrived; running against a folder nobody blocked and saying nothing is
      # how you come back later to a plan nobody touched and no record of why.
      #
      # Every bad token is reported, not just the first, because stopping at
      # the first one hides the rest of the answer.
      #
      # @param targets [Array<OpenLanes::Lifecycle::Unblocker::Target>]
      # @return [void]
      def refused(targets)
        problems = targets.reject(&:drainable?)
        return if problems.empty?

        problems.each do |target|
          state = target.subject ? target.subject.status.key : "unknown"
          puts "#{target.token}\t#{state}\t0 open\t#{PROBLEMS.fetch(target.problem)}"
        end
        return if @quiet

        error("#{problems.size} of the plans named cannot be drained:\n\n" +
              problems.map { |t| "  #{t.token} — #{PROBLEMS.fetch(t.problem)}" }.join("\n") +
              "\n\nThe tree holds: #{@tree.ordinals.join(", ")}")
      end

      # What each folder is waiting on, said BEFORE the agent is invoked.
      #
      # A real run hands the folder to an agent that can take a quarter of an
      # hour, and until it came back the terminal used to show nothing at
      # all: a run that had found nothing to do and a run still working
      # looked exactly alike.
      #
      # @param subjects [Array<OpenLanes::Plans::Subject>]
      # @return [void]
      def preflight(subjects)
        return if @quiet

        subjects.each do |subject|
          questions = Unblocker.questions(subject)
          answered = questions.count(&:answered)
          say("#{paint(subject.feature.ordinal.to_s, :bright_black)} #{subject.status.emoji} " \
              "#{subject.feature.title} — #{summary(questions.size, answered)}")
          detail(subject, questions)
        end
      end

      # @param open [Integer]
      # @param answered [Integer]
      # @return [String]
      def summary(open, answered)
        return "nothing open" if open.zero?

        "#{open} open, #{answered.zero? ? "none answered yet" : "#{answered} with an answer waiting"}"
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @param questions [Array<OpenLanes::Lifecycle::Unblocker::Question>]
      # @return [void]
      def detail(subject, questions)
        if subject.unreadable_block?
          say("  #{paint("blocked.md names no `## B<n>` question, so nothing here can be drained", :red)}",
            bullet: " ")
          say("  #{paint("Number each open question `## B1`, `## B2`, and each answer `## A1`, `## A2`.", :yellow)}",
            bullet: " ")
        elsif questions.empty?
          say("  #{paint("nothing left open", :green)}", bullet: " ")
        else
          questions.each { |question| say("  #{paint(question.to_s, :yellow)}", bullet: " ") }
        end
      end

      # One plan, after the fact: the deliverable line on STDOUT, and what
      # changed on STDERR.
      #
      # @param outcome [OpenLanes::Lifecycle::Unblocker::Outcome]
      # @return [void]
      def report(outcome)
        moved = movement(outcome)
        puts "#{outcome.ordinal}\t#{outcome.ok ? outcome.subject.status.key : "failed"}\t" \
             "#{outcome.after.size} open\t#{moved}\t#{outcome.note}"
        # A dry run changed nothing, so the preflight above it is still the
        # whole truth. Printing the same lines again reads as a second pass
        # that found the same thing, which is not what happened.
        return if @quiet || @dry_run

        say("#{paint(outcome.ordinal.to_s, :bright_black)} #{outcome.subject.status.emoji} " \
            "#{outcome.subject.feature.title} — #{paint(moved, outcome.ok ? :green : :red)}")
        detail(outcome.subject, outcome.after)
      end

      # What the file says happened, rather than what the agent claims. The
      # questions are counted off disk on both sides of the run.
      #
      # @param outcome [OpenLanes::Lifecycle::Unblocker::Outcome]
      # @return [String]
      def movement(outcome)
        return "failed" unless outcome.ok
        return "not attempted" if @dry_run
        return "blocked.md retired" if outcome.cleared?
        return "nothing folded" if outcome.folded.empty?

        "folded #{outcome.folded.map { |n| "B#{n}" }.join(", ")}"
      end

      # @param outcomes [Array<OpenLanes::Lifecycle::Unblocker::Outcome>]
      # @return [void]
      def footer(outcomes)
        if @dry_run
          warn("Dry run: no agent was invoked, and #{outcomes.size} " \
               "plan#{"s" unless outcomes.size == 1} #{outcomes.size == 1 ? "is" : "are"} unchanged.\n" \
               "Re-run without --dry-run to fold in whatever has been answered.")
          return
        end

        failed = outcomes.reject(&:ok)
        return error(failed.map { |o| "#{o.ordinal}: #{o.note}" }.join("\n")) unless failed.empty?

        success(tally(outcomes))
      end

      # @param outcomes [Array<OpenLanes::Lifecycle::Unblocker::Outcome>]
      # @return [String]
      def tally(outcomes)
        cleared = outcomes.count(&:cleared?)
        folded = outcomes.sum { |o| o.folded.size }
        waiting = outcomes.sum { |o| o.after.size }
        text = "#{folded} question#{"s" unless folded == 1} folded in · " \
               "#{cleared} plan#{"s" unless cleared == 1} out of the block · " \
               "#{waiting} still waiting on a human."
        return text unless folded.zero?

        "#{text}\n\nNothing moved. An answer has to be written into blocked.md as its own " \
          "`## A<n>` section, answering the `## B<n>` of the same number, before " \
          "there is anything to fold."
      end

      # The most serious thing that happened, as an exit status. A tree that
      # was partly drained still exits non-zero when part of it could not be.
      #
      # @param targets [Array<OpenLanes::Lifecycle::Unblocker::Target>]
      # @param outcomes [Array<OpenLanes::Lifecycle::Unblocker::Outcome>]
      # @return [Integer]
      def worst(targets, outcomes)
        problems = targets.map(&:problem)
        return 66 if problems.include?(:missing)
        return 65 if problems.include?(:not_blocked)
        return 1 unless outcomes.all?(&:ok)

        0
      end
    end
  end
end

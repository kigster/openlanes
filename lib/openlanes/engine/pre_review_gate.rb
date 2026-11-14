# frozen_string_literal: true

module OpenLanes
  module Engine
    # Runs the project's own lint and test commands in a plan's checkout
    # before any reviewer starts.
    #
    # A builder is told to leave the suite green ({Execution::Checks}), and
    # one that did not still signed Completed: three reviewers then spent a
    # round each rejecting the plan for a red suite the harness could have
    # seen in minutes for free. The commands are the ones {Execution::Checks}
    # already derives from the checkout, so the builder's instruction and
    # the gate cannot name different things.
    class PreReviewGate
      # What the gate found. `log_tail` is the last {TAIL} lines of the
      # failing command's output, for the builder's mail; empty when green.
      Verdict = Data.define(:passed, :reason, :log_tail) do
        # @return [Boolean]
        def passed? = passed
      end

      # Lines of output kept for the builder: enough to name the failures,
      # few enough to read in a mail.
      TAIL = 40

      # Seconds one command may run before the gate calls it red.
      TIMEOUT = 900

      class << self
        # @param checkout [String] the plan's checkout
        # @param timeout [Numeric] seconds per command
        # @param commands [Array<String>, nil] nil derives them from the checkout
        # @param spawner [#spawn]
        # @return [Verdict]
        def call(checkout, timeout: TIMEOUT, commands: nil, spawner: Spawner::System)
          new(checkout, timeout:, commands:, spawner:).call
        end
      end

      # @param checkout [String]
      # @param timeout [Numeric]
      # @param commands [Array<String>, nil]
      # @param spawner [#spawn]
      def initialize(checkout, timeout:, commands:, spawner:)
        @checkout = checkout
        @timeout = timeout
        @commands = commands || Execution::Checks.commands(checkout)
        @spawner = spawner
      end

      # @return [Verdict]
      def call
        # Nothing recognisable to run is not a red suite: the reviewers still
        # read the work, as they did before the gate existed.
        return Verdict.new(passed: true, reason: "no checks found", log_tail: "") if @commands.empty?

        @commands.each do |command|
          verdict = run(command)
          return verdict unless verdict.passed?
        end
        Verdict.new(passed: true, reason: "#{@commands.join(", ")} passed", log_tail: "")
      end

      private

      # @param command [String]
      # @return [Verdict]
      def run(command)
        status, output = capture(command)
        return red("`#{command}` timed out after #{@timeout}s", output) if status.nil?
        return Verdict.new(passed: true, reason: "`#{command}` passed", log_tail: "") if status.success?

        red("`#{command}` exited #{status.exitstatus.inspect}", output)
      end

      # @param command [String]
      # @return [Array(Process::Status, String), Array(nil, String)] nil
      #   status when the command outlived {#initialize}'s timeout
      def capture(command)
        child = Execution::Child.spawn(["sh", "-c", command], chdir: @checkout, spawner: @spawner)
        output = +""
        reader = Thread.new { child.each_chunk { output << it } }
        return [child.wait, output] if reader.join(@timeout)

        child.terminate
        reader.join
        [nil, output]
      end

      # @return [Verdict]
      def red(reason, output)
        tail = output.scrub.lines.last(TAIL).join
        Verdict.new(passed: false, reason:, log_tail: tail)
      end
    end
  end
end

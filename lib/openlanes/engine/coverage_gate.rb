# frozen_string_literal: true

require "shellwords"
require "tempfile"

module OpenLanes
  module Engine
    # Decides whether a pull request's checkout has earned `ready-to-merge` on
    # coverage (decision M15): runs the test command the checkout's
    # `.openlanes.yml` declares under `coverage:`, reads the line figure (from
    # the report it wrote, or from what `report_command` prints), and compares
    # it with the declared minimum.
    #
    # A checkout with no `coverage:` section withholds too, but as
    # {Verdict#unconfigured?}: nothing was measured, so nothing failed, and
    # the verifier sends the pull request back for the section rather than
    # for a defect.
    #
    # Everything that is not a clean, fresh, readable report at or above the
    # minimum withholds, each with its reason. In particular the command's
    # own verdict comes first: a suite that fails can still leave a report
    # behind, and a figure from a red run is not one to merge on.
    #
    # Nothing applies `ready-to-merge` yet. The verifier (plan 014) or
    # `Vcs::Review` (plan 005), whichever lands second, asks this gate before
    # setting the label and refuses with {Verdict#reason}.
    #
    # Running a project's command is arbitrary code, so it runs only in the
    # checkout it is handed, never the main tree, and through the same
    # {Execution::Child} the executor uses: its own process group, the
    # environment Bundler was loaded under, and every process reaped when the
    # harness exits.
    class CoverageGate
      # Seconds a test command may run before it is stopped and counted as 0%.
      TIMEOUT = 1800

      # Lines of the command's output a withheld verdict keeps.
      TAIL = 20

      # @!attribute [r] passed
      #   @return [Boolean]
      # @!attribute [r] percent
      #   @return [Float] the line figure the decision used; 0.0 when the
      #     report said nothing or the command failed
      # @!attribute [r] minimum
      #   @return [Float, nil] nil when the project declares no coverage
      # @!attribute [r] reason
      #   @return [String] one sentence, the figure and the minimum included,
      #     fit for a refusal or a PR comment
      # @!attribute [r] config
      #   @return [OpenLanes::Coverage::Config, nil]
      # @!attribute [r] output
      #   @return [Array<String>] the command's last {TAIL} lines; empty when
      #     it never ran
      # @!attribute [r] unconfigured
      #   @return [Boolean] withheld only because the checkout's
      #     `.openlanes.yml` has no `coverage:` section
      Verdict = Data.define(:passed, :percent, :minimum, :reason, :config, :output, :unconfigured) do
        def initialize(percent: 0.0, minimum: nil, config: nil, output: [], unconfigured: false, **rest) = super

        alias_method :passed?, :passed
        alias_method :unconfigured?, :unconfigured

        # @return [Boolean]
        def withheld? = !passed

        # @return [String]
        def to_s = passed ? reason : "#{Plans::ReviewLabel::READY_TO_MERGE} withheld: #{reason}"
      end

      # What one run of the command left behind.
      Run = Data.define(:status, :timed_out, :output, :started)

      # @param timeout [Numeric] seconds, see {TIMEOUT}
      # @param spawner [#spawn] {Execution::Child}, or a stand-in answering
      #   `spawn(argv, chdir:)` with something that has `each_chunk`, `wait`
      #   and `terminate`
      def initialize(timeout: TIMEOUT, spawner: Execution::Child)
        @timeout = timeout
        @spawner = spawner
      end

      # @param checkout [#path, #dirty?] the pull request's checkout, such as
      #   a {Vcs::Worktree::Checkout}
      # @return [Verdict]
      def call(checkout:)
        root = checkout.path
        return withhold("#{root} has uncommitted changes; coverage is measured only in a clean checkout") if checkout.dirty?

        config = Coverage.config(root)
        unless config
          return Verdict.new(passed: false,
            unconfigured: true,
            reason: "#{OpenLanes::Config::FILE} in #{root} has no #{Coverage::Config::SECTION}: section, so nothing was measured")
        end

        judge(config, root, run(config.command, root))
      rescue Coverage::Invalid => e
        withhold(e.message)
      end

      # Floors exactly. Flooring `percent * 100` as a Float printed 10.03 as
      # 10.02%, because the product is 1002.9999999999999; a Float is read
      # back as the shortest decimal it prints as, which is the one it meant.
      #
      # @param percent [Rational, Float] {Coverage::Report#ratio} where there is one
      # @return [String] floored to two decimals, so 94.995 never prints as
      #   the 95.00 it did not reach
      def self.figure(percent)
        exact = percent.is_a?(Float) ? Rational(percent.to_s) : percent.to_r
        format("%.2f%%", exact.floor(2))
      end

      private

      # @return [Verdict]
      def judge(config, root, run)
        source = config.source
        failed = failure(config, root, run)
        return withhold("coverage counts as 0%: #{failed}", config:, run:) if failed

        report = report_of(config, root)
        return withhold("coverage counts as 0%: #{report.problem}", config:, run:) unless report.read?

        figure = self.class.figure(report.ratio)
        minimum = format("%g%%", config.minimum)
        if report.ratio >= config.minimum
          Verdict.new(passed: true,
            percent: report.percent,
            minimum: config.minimum,
            config:,
            reason: "coverage #{figure} meets the #{minimum} minimum (#{source})",
            output: run.output)
        else
          withhold("coverage #{figure} is below the #{minimum} minimum (#{source})",
            config:,
            run:,
            percent: report.percent)
        end
      end

      # Why the run cannot be trusted, before its report is even read.
      #
      # @return [String, nil]
      def failure(config, root, run)
        return "`#{config.command}` ran past #{@timeout}s and was stopped" if run.timed_out
        return "`#{config.command}` exited #{run.status.exitstatus || run.status}" unless run.status.success?

        path = config.report_path(root)
        # A report_command reads whatever it reads; there is no file here
        # whose age could say whether the command wrote it.
        return unless path

        # A whole second's grace: some filesystems keep mtimes in seconds.
        return unless File.exist?(path) && File.mtime(path) < Time.at(run.started.to_i)

        "#{config.report} is older than this run, so the command did not write it"
      end

      # The figure, from the report file or from `report_command`'s STDOUT.
      #
      # @return [Coverage::Report]
      def report_of(config, root)
        return Coverage.read(format: config.format, path: config.report_path(root)) unless config.report_command?

        printed(config.report_command, root)
      end

      # What `report_command` printed, as a {Coverage::Report}, so it is
      # floored and compared exactly as a parsed report is: the number over
      # 100 lines, held as a Rational. Anything but one number from 0 to 100
      # is a report that could not be read, and counts as 0% the same way.
      # STDERR goes to a file of its own, because a warning `jq` prints is
      # not part of the figure.
      #
      # @return [Coverage::Report]
      def printed(command, root)
        Tempfile.create("openlanes-coverage-stderr") do |stderr|
          run = run("{ #{command}\n} 2>#{Shellwords.escape(stderr.path)}", root)
          return Coverage::Report.new(problem: "`#{command}` ran past #{@timeout}s and was stopped") if run.timed_out

          text = run.output.join("\n").strip
          figure = text.match?(/\A\d+(\.\d+)?\z/) && Rational(text)
          return Coverage::Report.new(covered: figure, relevant: 100) if run.status.success? && figure && figure <= 100

          said = run.status.success? ? "printed #{text.inspect}" : "exited #{run.status.exitstatus || run.status}"
          error = File.read(stderr.path).lines.first.to_s.strip
          Coverage::Report.new(problem: "`#{command}` #{said}, not a line percentage#{" (#{error})" unless error.empty?}")
        end
      end

      # @return [Run]
      def run(command, root)
        started = Clock::System.now
        child = @spawner.spawn(["sh", "-c", command], chdir: root)
        output = +""
        reader = Thread.new { child.each_chunk { output = keep_tail(output << it) } }
        timed_out = reader.join(@timeout).nil?
        if timed_out
          child.terminate
          reader.join
        end
        Run.new(status: child.wait, timed_out:, output: output.lines.last(TAIL).map(&:chomp), started:)
      end

      # Bounds memory on a chatty suite; only the tail is ever shown.
      #
      # @return [String]
      def keep_tail(text) = text.bytesize > 65_536 ? text.byteslice(-32_768..).scrub : text

      # @return [Verdict]
      def withhold(reason, config: nil, run: nil, percent: 0.0)
        Verdict.new(passed: false, percent:, minimum: config&.minimum, reason:, config:, output: run&.output || [])
      end
    end
  end
end

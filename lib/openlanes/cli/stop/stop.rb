# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes stop` — stops the factory (C1, S2): TERM to its supervisor,
    # which stops the engine and the page itself, then to any engine or page
    # left without one. `--all` stops every `openlanes run` in the project
    # too, and any agent whose engine or run is gone. Nothing is signalled that is not verified to be the process its
    # PID file names; a file that fails the check is removed instead.
    #
    # `--web` stops the control room's server alone and leaves the
    # supervisor, the engine and every agent running.
    class Stop < Base
      desc "Stop the factory: its supervisor, engine and control room; --all stops every `openlanes run` too, " \
           "--web the control room alone"

      dry_run_option "Signal nothing; print what would be stopped"
      option :all,
        type:    :boolean,
        default: false,
        desc:    "Every `openlanes run` in this project as well, and any agent left behind"
      option :web,
        type:    :boolean,
        default: false,
        aliases: ["-w"],
        desc:    "Only the control room's server; the engine and its agents stay up"

      example [
        "                # the factory",
        "--all           # the factory and every run",
        "--web           # the control room's server alone; the engine and its agents stay up",
        "-n --all        # what would be stopped"
      ]

      # What each outcome reads as.
      WORDS = {
        stopped:    "stopped",
        killed:     "killed: TERM was not enough",
        stale:      "not running: stale PID file removed",
        would_stop: "would stop"
      }.freeze

      # @param options [Hash]
      # @return [void]
      def call(**options)
        quiet?(options)
        dry_run = dry_run?(options)
        outcomes = outcomes_for(options, dry_run)
        return say("#{options[:web] ? "No control room" : "Nothing"} is running in #{Dir.pwd}.") if outcomes.empty?

        $stdout.write(UI.table(outcomes.map { row(it, dry_run) }, header: %w[PROCESS PID RESULT]))
        pending = outcomes.count { it.result == :would_stop }
        $stdout.flush
        dry_run_footer(pending, pending == 1 ? "process" : "processes")
      end

      private

      # @param options [Hash]
      # @param dry_run [Boolean]
      # @return [Array<OpenLanes::Supervision::Stopper::Outcome>]
      def outcomes_for(options, dry_run)
        stopper = Supervision.stopper(root: Dir.pwd)
        return stopper.call(runs: options[:all], dry_run:) unless options[:web]

        # One asks for less than `stop`, the other for more.
        refuse("Pass --web or --all, not both: --web stops the control room alone.", 64) if options[:all]
        stopper.web(dry_run:)
      end

      # @param outcome [OpenLanes::Supervision::Stopper::Outcome]
      # @param dry_run [Boolean]
      # @return [Array<String>]
      def row(outcome, dry_run)
        file = outcome.file
        word = outcome.result == :stale && dry_run ? "not running: stale PID file" : WORDS.fetch(outcome.result)
        [file ? Status.label(file) : File.basename(outcome.path), file&.pid.to_s, word]
      end
    end
  end
end

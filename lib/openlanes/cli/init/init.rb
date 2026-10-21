# frozen_string_literal: true

require "fileutils"
require "tty-prompt"

module OpenLanes
  module CLI
    # `openlanes init` — make a directory a project: `.openlanes.yml` and `.plans/`.
    #
    # It decides its own root rather than searching for one, because it is
    # the command that creates what the search looks for.
    class Init < Base
      standalone!
      desc "Write .openlanes.yml at the project root and create the plans directory"

      option :project, desc: "Heading for INDEX.md and similar (default: the root's directory name)"
      option :lane,
        values: Plans::Spec::LANES.map(&:to_s),
        desc:   "Default lane for `openlanes create`: full, plan or quick (default: full)"
      option :frontend,
        type: :boolean,
        desc: "Whether plans have a front end; leave it out to let each plan decide"
      option :jobs, aliases: ["-j"], desc: "How many plans `openlanes run` works on at once (default: cores - 2)"
      option :quality,
        values: Config::QUALITIES.map(&:to_s),
        desc:   "desired_codebase_quality: high, standard or mvp (R4); asked on a terminal when left out"
      option :yes,
        type:    :boolean,
        default: false,
        aliases: ["-y"],
        desc:    "Ask nothing; take the flags and the defaults"
      dry_run_option "Write nothing; print the file that would be written"
      option :overwrite,
        type:    :boolean,
        default: false,
        desc:    "Replace an existing .openlanes.yml, which is otherwise kept"

      example [
        "                                   # ask for each value on a terminal",
        "-y --project 'Equilibris App'       # ask nothing",
        "-y --lane plan --no-frontend -j 4   # a command-line tool, four plans at once",
        "-n                                  # show the file, write nothing"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        quiet?(options)
        prepare(options)
        root = Project.init_root
        path = File.join(root, Config::FILE)
        plans = File.expand_path(options.fetch(:dir, OpenLanes::PLANS_DIR), root)
        keep = File.file?(path) && !options[:overwrite]

        config = keep ? Config.load(root) : settings(root, options)
        return preview(path, plans, config, keep) if dry_run?(options)
        return unless keep || confirmed?(path, options)

        File.write(path, config.to_yaml) unless keep
        FileUtils.mkdir_p(plans)
        decide(plans, config) unless keep
        puts path
        report(path, plans, keep, options)
      rescue OpenLanes::Error => e
        refuse(e.message, 65)
      end

      private

      # `openlanes setup`, but only when the machine is not ready, so a new
      # project goes setup, init, start in one go and a ready machine is
      # not made to wait on brew. A check that still fails is reported and
      # init carries on: the file it writes needs none of them.
      #
      # @param options [Hash]
      # @return [void]
      def prepare(options)
        return if machine.ready?

        UI.line("This machine is missing something openlanes needs; running openlanes setup first.")
        outcome = machine.call(dry_run: dry_run?(options))
        $stderr.write(OpenLanes::Setup.render(outcome.checks))
        warn("Still not ready: run each fix above, then openlanes setup.") unless outcome.ok?
      end

      # A named seam, so a spec can stand in for brew, gh and Redis.
      #
      # @return [OpenLanes::Setup::Machine]
      def machine = @machine ||= OpenLanes::Setup.machine

      # The five values, each from its flag, else asked on a terminal, else
      # its default. The result is parsed back as the file would be, so
      # `init` cannot write a file every other command then refuses.
      #
      # @param root [String]
      # @param options [Hash]
      # @return [OpenLanes::Config]
      def settings(root, options)
        ask = interactive?(options)
        project = options[:project] || (ask ? prompt.ask("Project name:", default: File.basename(root)) : File.basename(root))
        lane = options[:lane] || (ask ? prompt.select("Default lane for new plans:", Plans::Spec::LANES.map(&:to_s)) : "full")
        frontend = options.key?(:frontend) ? options[:frontend] : (ask_frontend if ask)
        jobs = options[:jobs] || (prompt.ask("Plans to run at once (blank: cores - 2):") if ask)
        quality = options[:quality] || (ask_quality if ask)

        draft = Config.new(project:, lane: lane.to_sym, frontend:, jobs: count(jobs), desired_codebase_quality: quality&.to_sym)
        Config.parse(draft.to_yaml, path: File.join(root, Config::FILE))
      end

      # @return [Boolean, nil]
      def ask_frontend
        choice = prompt.select("Do plans have a front end?", ["each plan decides", "YES", "NO"])
        { "YES" => true, "NO" => false }[choice]
      end

      # R4's question, always put on a terminal (plan 035), in the words
      # {Engine::QualityQuestion::CHOICES} gives the page. Left unanswered
      # only under -y, where the run asks it before any work starts.
      #
      # @return [String]
      def ask_quality
        prompt.select("#{Engine::QualityQuestion::HEADING}. #{Engine::QualityQuestion::BODY}",
          Engine::QualityQuestion::CHOICES.to_h { [it.label, it.quality.to_s] })
      end

      # The quality chosen, written down in `decisions.md` with every
      # option it was chosen from.
      #
      # @param plans [String]
      # @param config [OpenLanes::Config]
      # @return [void]
      def decide(plans, config)
        return if config.quality_unset?

        Engine::QualityQuestion.record(plans, config.desired_codebase_quality, by: "openlanes init")
      end

      # @param value [String, Integer, nil]
      # @return [Integer, nil]
      def count(value)
        return nil if value.nil? || value.to_s.strip.empty?
        return value.to_s.to_i if value.to_s.match?(/\A[1-9]\d*\z/)

        refuse("--jobs must be a whole number above zero, not #{value.inspect}.", 64)
      end

      # @param path [String]
      # @param options [Hash]
      # @return [Boolean]
      def confirmed?(path, options)
        return true unless interactive?(options)
        return true if prompt.select("Write #{path}?", %w[YES NO]) == "YES"

        warn("Nothing was written.") unless quiet?(options)
        false
      end

      # Prompts only for a person at a terminal who did not say -y: a script
      # or a pipe gets the flags and the defaults, never a question it
      # cannot answer.
      #
      # @param options [Hash]
      # @return [Boolean]
      def interactive?(options) = !options[:yes] && tty?

      # @return [Boolean]
      def tty? = $stdin.tty? && $stderr.tty?

      # A named seam, so a spec can answer the questions.
      #
      # @return [TTY::Prompt]
      def prompt
        @prompt ||= TTY::Prompt.new(output: $stderr)
      end

      # @return [void]
      def preview(path, plans, config, keep)
        $stdout.write(config.to_yaml)
        warn("Dry run — nothing was written.\n" \
             "#{keep ? "Would keep" : "Would write"} #{path}" \
             "#{"\nWould create #{plans}" unless File.directory?(plans)}\n\n" \
             "Re-run without --dry-run to apply.")
      end

      # @return [void]
      def report(path, plans, keep, options)
        return if quiet?(options)

        success("#{keep ? "Kept" : "Wrote"} #{path}#{" (--overwrite replaces it)" if keep}\n" \
                "Plans live in #{plans}\n\nNext: openlanes create <a few words>")
      end
    end
  end
end

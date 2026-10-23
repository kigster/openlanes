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
        desc:   "desired_codebase_quality: high or mvp (R4); leave it out to be asked on the first ok-not-perfect review"
      option :ci,
        values: Config::CI_PROVIDERS.map(&:to_s),
        desc:   "What checks pull requests: github_actions, circleci, jenkins, external or none " \
                "(-y default: what the folder runs, else none)"
      option :merge_by, values: Config::MERGERS.map(&:to_s), desc: "Who merges a reviewed pull request (default: human)"
      option :reconfigure,
        type:    :boolean,
        default: false,
        desc:    "Ask again with the current answers as defaults; show the diff before writing"
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
        "-y --ci github_actions --merge-by auto --quality mvp",
        "--reconfigure                       # ask again, show what changed",
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
        reconfigure = options[:reconfigure] && File.file?(path)
        keep = File.file?(path) && !options[:overwrite] && !reconfigure

        config = if keep
                   Config.load(root)
                 else
                   settings(root, options, reconfigure ? Config.load(root) : Config.new)
                 end
        changes = reconfigure ? diff(root, path, config) : nil
        return preview(path, plans, config, keep, changes) if dry_run?(options)

        $stdout.write(changes) if changes
        return unless keep || confirmed?(path, options)

        write(root, path, config) unless keep
        FileUtils.mkdir_p(plans)
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

      # Every value, from its flag, else asked on a terminal, else the
      # current file under --reconfigure, else its default. The result is
      # parsed back as the file would be, so `init` cannot write a file
      # every other command then refuses.
      #
      # @param root [String]
      # @param options [Hash]
      # @param current [OpenLanes::Config]
      # @return [OpenLanes::Config]
      def settings(root, options, current)
        ask = interactive?(options)
        interview = OpenLanes::Setup.interview(root:,
          prompt:    ask ? prompt : nil,
          extractor: ask ? OpenLanes::Setup.extractor : nil,
          defaults:  current,
          given:     given(options),
          ask:)
        draft = interview.call
        Config.parse(draft.to_yaml, path: File.join(root, Config::FILE))
      end

      # The flags typed, checked here because a spec or a script calling
      # {#call} skips dry-cli's own `values:` check.
      #
      # @param options [Hash]
      # @return [Hash{Symbol => Object}]
      def given(options)
        given = options.slice(:project, :lane).compact
        given[:frontend] = options[:frontend] if options.key?(:frontend)
        given[:jobs] = count(options[:jobs]) if options[:jobs]
        given[:ci] = member(:ci, options[:ci], Config::CI_PROVIDERS) if options[:ci]
        given[:merge_by] = member(:merge_by, options[:merge_by], Config::MERGERS) if options[:merge_by]
        given[:desired_codebase_quality] = member(:quality, options[:quality], Config::QUALITIES) if options[:quality]
        given
      end

      # @return [Symbol]
      def member(flag, value, values)
        word = value.to_s.strip.downcase.to_sym
        return word if values.include?(word)

        refuse("--#{flag.to_s.tr("_", "-")} must be one of #{values.join(", ")}, not #{value.inspect}.", 64)
      end

      # @param value [String, Integer, nil]
      # @return [Integer, nil]
      def count(value)
        return nil if value.nil? || value.to_s.strip.empty?
        return value.to_s.to_i if value.to_s.match?(/\A[1-9]\d*\z/)

        refuse("--jobs must be a whole number above zero, not #{value.inspect}.", 64)
      end

      # `.openlanes.yml`, `docs/decisions/stack.md` when the stack is known,
      # and the CI file when openlanes scaffolds the provider and the folder
      # does not already run it.
      #
      # @return [void]
      def write(root, path, config)
        File.write(path, config.to_yaml)
        stack = config.stack && OpenLanes::Setup::Stack.from_h(config.stack)
        OpenLanes::Setup::StackDocument.new(stack).write(root) if stack
        provider = config.ci&.dig(:provider)
        return unless OpenLanes::Setup::CiScaffold.providers.include?(provider)
        return if OpenLanes::Setup.detect_ci(root).any? { it.provider == provider }

        OpenLanes::Setup::CiScaffold.new(root, provider:, stack: OpenLanes::Setup::Stack.from_h(config.stack)).call
      end

      # What --reconfigure would change, file by file, as removed and added lines.
      #
      # @return [String] "No changes." when nothing changes
      def diff(root, path, config)
        stack = config.stack ? OpenLanes::Setup::StackDocument.new(OpenLanes::Setup::Stack.from_h(config.stack)).render : ""
        doc = File.join(root, OpenLanes::Setup::StackDocument::PATH)
        [[path, config.to_yaml], [doc, stack]].filter_map { |file, after|
          before = File.file?(file) ? File.read(file) : ""
          next if before == after

          old, new = before.lines.map(&:chomp), after.lines.map(&:chomp)
          ["--- #{file}", *(old - new).map { "- #{it}" }, *(new - old).map { "+ #{it}" }].join("\n")
        }.then { it.empty? ? "No changes.\n" : "#{it.join("\n\n")}\n" }
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
      def preview(path, plans, config, keep, changes = nil)
        $stdout.write(changes || config.to_yaml)
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

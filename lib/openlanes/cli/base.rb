# frozen_string_literal: true

require "dry/cli"

module OpenLanes
  module CLI
    # Shared flags and the plumbing every command needs.
    class Base < Dry::CLI::Command
      include UI

      # dry-cli gathers every token a command did not declare an argument for
      # into :args, and hands it over without a word. `openlanes docs
      # .plans/README.md` — the `-o` forgotten — therefore ran with every
      # default, wrote the conventions to the default path, and printed
      # success for a file the caller never named.
      #
      # Prepended rather than called from each `call`, because the command
      # that forgets this check is the one that needed it.
      module RefuseStrayArguments
        # @param options [Hash]
        # @return [void]
        def call(**options)
          stray = Array(options[:args]) - self.class.arguments.flat_map { Array(options[it.name.to_sym]) }
          unless stray.empty?
            refuse("This command takes no argument like #{stray.join(" ")}.\n" \
                   "An option it does take may be the one you meant: run it with -h.",
              64)
          end

          super
        end
      end

      # Every project command starts at the project root, wherever it was
      # typed: a `.plans` found relative to a subdirectory is a `.plans` that
      # does not exist, and the refusal that follows names the wrong problem.
      #
      # Prepended for the same reason as {RefuseStrayArguments}: the command
      # that forgets to look is the one that runs against the wrong tree.
      module EnterProject
        # @param options [Hash]
        # @return [void]
        def call(**options)
          enter_project(options) unless self.class.standalone?
          super
        end
      end

      # Marks a command that needs no project — reference output, the agent
      # roster, completion — so it runs from anywhere without the search.
      #
      # @return [void]
      def self.standalone! = @standalone = true

      # @return [Boolean]
      def self.standalone? = @standalone == true

      # The name this command is typed as, and the key its section takes
      # under `commands:` in `.openlanes.yml`: "run", "resync dirs", "list-plans".
      #
      # @return [String, nil] nil for a class with no name, as in a spec
      def self.command_name
        return nil unless name

        name.delete_prefix("OpenLanes::CLI::").split("::")
            .map { OpenLanes.inflector.underscore(it).tr("_", "-") }.join(" ")
      end

      # dry-cli merges what was typed over these, so a `.openlanes.yml` value
      # placed here sits exactly between the flag and the built-in default.
      # A file that cannot be read adds nothing at this point; {#enter_project}
      # reads it again and refuses with the reason.
      #
      # @return [Hash{Symbol => Object}]
      def self.default_params
        return super if standalone? || command_name.nil?

        root = Project.root or return super
        known = options.map(&:name)
        super.merge(OpenLanes::Config.load(root).for(command_name).slice(*known))
      rescue OpenLanes::Error
        super
      end

      # Every `commands:` section must name a command that exists, and every
      # key in it an option that command takes, with a value it accepts. Each
      # project command checks the whole file, not only its own section: a
      # typo under a command you rarely run is still a typo.
      #
      # @param config [OpenLanes::Config]
      # @return [void]
      # @raise [OpenLanes::Error]
      def self.check_config!(config)
        config.commands.each do |name, settings|
          command = OpenLanes::CLI.get(name.split).then { it.found? ? it.command : nil }
          unless command.respond_to?(:command_name) && command.command_name == name
            raise OpenLanes::Error, "#{config.path}: commands.#{name}: no such command"
          end

          settings.each { |key, value| check_option!(config, command, name, key, value) }
        end
      end

      # @return [void]
      def self.check_option!(config, command, name, key, value)
        where = "#{config.path}: commands.#{name}.#{key}"
        option = command.options.find { it.name == key }
        raise OpenLanes::Error, "#{where}: #{name} takes no such option" unless option
        raise OpenLanes::Error, "#{where}: a preview is asked for each time, never set as a default" if key == :dry_run

        if option.boolean? && ![true, false].include?(value)
          raise OpenLanes::Error, "#{where}: #{value.inspect} is not true or false"
        end
        return unless option.values && !option.values.map(&:to_s).include?(value.to_s)

        raise OpenLanes::Error, "#{where}: #{value.inspect} is not one of #{option.values.join(", ")}"
      end
      private_class_method :check_option!

      def self.inherited(klass)
        super
        klass.prepend(EnterProject)
        klass.prepend(RefuseStrayArguments)
        klass.option :dir,
          default: OpenLanes::PLANS_DIR,
          aliases: ["-D"],
          desc:    "The .plans directory"
        klass.option :quiet,
          type:    :boolean,
          default: false,
          aliases: ["-q"],
          desc:    "Suppress progress output on STDERR"
      end

      # Declares `-n` / `--dry-run` on a command that changes something.
      #
      # @param desc [String] what the preview prints instead of doing
      # @return [void]
      def self.dry_run_option(desc)
        option :dry_run,
          type:    :boolean,
          default: false,
          aliases: ["-n"],
          desc:
      end

      private

      # @param options [Hash]
      # @return [OpenLanes::Plans::Tree]
      def tree_for(options)
        tree = Plans.tree(options.fetch(:dir, OpenLanes::PLANS_DIR))
        unless tree.exist?
          refuse("No #{OpenLanes::PLANS_DIR} directory at\n#{tree.dir}\n\n" \
                 "Run `openlanes init` to create it, or pass -D.",
            66)
        end
        tree
      end

      # The directory the command was typed in, before {EnterProject} moved
      # to the root. A path the user typed (`--prompt notes.md`) means a file
      # beside them, not one beside `.plans`.
      #
      # @return [String]
      def origin = @origin || Dir.pwd

      # @param path [String, nil]
      # @return [String, nil] +path+ as the user meant it, from {#origin}
      def typed_path(path) = path && File.expand_path(path, origin)

      # Finds the root and moves there, saying so when that is somewhere
      # else. `-D` and `PLANS_DIR` are relative, so they resolve against the
      # root from here on.
      #
      # @param options [Hash]
      # @return [void]
      def enter_project(options)
        @origin = Dir.pwd
        root = Project.root(from: @origin)
        unless root
          refuse("No project here: nothing in #{@origin} or above it holds " \
                 "#{Project::FILE}, #{OpenLanes::PLANS_DIR}/ or .git.\n\n" \
                 "Run `openlanes init` to make this directory one.",
            66)
        end
        check_config(root)
        return if root == Project.expand(@origin)

        Dir.chdir(root)
        UI.line("Project root: #{root}") unless options.fetch(:quiet, false)
      end

      # @param root [String]
      # @return [void]
      def check_config(root)
        self.class.check_config!(OpenLanes::Config.load(root))
      rescue OpenLanes::Error => e
        refuse(e.message, 65)
      end

      # Report and stop, in the shape every refusal here takes. The statuses
      # follow sysexits where one fits: 64 usage, 65 bad data, 66 no input,
      # 69 a service (GitHub, Linear) refused us.
      #
      # @param message [String]
      # @param status [Integer]
      # @return [void] never returns
      def refuse(message, status)
        error(message)
        exit status
      end

      # @param options [Hash]
      # @return [Boolean]
      def quiet?(options)
        quiet = options.fetch(:quiet, false)
        UI.quiet = quiet
        quiet
      end

      # `-n` / `--dry-run`. A command does the work it is named for, so the
      # preview is what has to be asked for, never the work itself.
      #
      # @param options [Hash]
      # @return [Boolean]
      def dry_run?(options) = options.fetch(:dry_run, false)

      # The credential warning {Execution.credentials_notice} words, drawn
      # when there is one to give.
      #
      # @return [void]
      def credentials_warning
        notice = Execution.credentials_notice
        warn(notice) if notice
      end

      # The success value of a workflow's result, or the refusal it failed
      # with, reported and exited on. One shape for every workflow, so a
      # command reads the same whichever one it calls.
      #
      # @param result [Dry::Monads::Result] Success(value) or Failure({Refusal})
      # @return [Object] the success value; a failure never returns
      def unwrap(result) = result.value_or { |refusal| refuse(refusal.message, refusal.status) }

      # The line every dry run ends with, so nobody mistakes a preview for the
      # thing having happened.
      #
      # @param count [Integer] how much work is pending
      # @param what [String]
      # @return [void]
      def dry_run_footer(count, what)
        return if count.zero?

        warn("#{count} #{what} pending — nothing was changed.\nRe-run without --dry-run to apply.")
      end
    end
  end
end

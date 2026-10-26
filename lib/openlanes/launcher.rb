module OpenLanes
  class Launcher
    # The one flag every command takes, so no command declares it. Removed
    # from the arguments before dry-cli sees them, which would otherwise
    # reject it as an argument the command never asked for.
    NO_COLOR_FLAGS = %w[--no-color -C].freeze

    attr_accessor :argv,
      :stdin,
      :stdout,
      :stderr,
      :kernel

    def initialize(argv,
      stdin = $stdin,
      stdout = $stdout,
      stderr = $stderr,
      kernel = Kernel)
      self.argv   = argv
      self.stdin  = stdin
      self.stdout = stdout
      self.stderr = stderr
      self.kernel = kernel

      # Bare `openlanes` prints its help. It used to print the plan table, which
      # meant the one command that reads a tree was also the one you got by accident.
      @argv = argv.empty? ? %w(-h) : argv

      # `run --push-pr` takes an OPTIONAL part letter: bare means "continue this
      # plan"s sequence", `--push-pr C` means "use C". dry-cli has no optional-value
      # option, so the bare form is filled in here rather than made to look like a
      # mistake.
      #
      # Scoped to `run`, and to the long spelling when it is not. This rewrote every
      # `-p` in every command for a while, which quietly turned
      # `linear import TAX -p "Some Project"` into `-p auto "Some Project"` — the
      # option took "auto" and the project name became a stray argument. A global
      # rewrite of a one-letter flag will collide with the next command that wants
      # it; this one collided within the week.
      return unless argv.first == "run"

      @argv = argv.each_with_object([]) do |token, out|
        out << token
        next unless ["--push-pr", "-p"].include?(token)

        following = argv[argv.index(token) + 1]
        out << "auto" unless following&.match?(/\A[A-Z]\z/)
      end
    end

    # `--no-color` becomes NO_COLOR rather than a setting of its own: the help
    # screens, the runtime UI and every child process already honour it, so
    # one variable switches all three off together.
    #
    # @return [void] never returns; exits with the command's status
    #
    # A command that raises fails, whatever it raised. `code` starts at 1 and
    # becomes 0 only once the command returns, because the `ensure` below
    # exits in place of any exception still in flight: a LoadError, which is
    # a ScriptError and so no StandardError, once left `openlanes --help`
    # printing nothing and exiting 0.
    def execute!
      ENV["NO_COLOR"] = "1" if NO_COLOR_FLAGS.intersect?(argv)
      code = 1
      Dry::CLI.new(::OpenLanes::CLI).call(arguments: argv - NO_COLOR_FLAGS)
      code = 0
    rescue SystemExit => e
      code = e.status
    rescue StandardError, ScriptError => e
      stderr.puts UI.paint("Error: #{e.message}", :red)
    ensure
      kernel.exit(code)
    end
  end
end

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

# frozen_string_literal: true

require "fileutils"
require "semantic_logger"

module OpenLanes
  # The one place a process sets SemanticLogger up, so the engine and the
  # control room's server write the same file the same way.
  #
  # `openlanes run` and `openlanes start` log as `engine`; the server they
  # spawn, and `openlanes web` alone, log as `web`. Both append to
  # `<project root>/log/development.log` unless told otherwise, and the
  # engine hands its server the file, level and format through {Settings#env},
  # so a `--log` typed on `run` moves both processes rather than one.
  #
  # Two processes share one file safely because each opens it in append mode
  # and writes a whole line per call: the kernel puts every O_APPEND write at
  # the end, so lines from the two interleave but never tear. Each line carries
  # its process id, which is how a reader tells them apart.
  #
  # Logging is synchronous. SemanticLogger's default background thread keeps
  # its queue in memory, and a CLI that exits, is killed by its own run, or is
  # TERMed by {Web::Launcher#stop} would take the last lines with it.
  #
  # @example
  #   Log.setup(Log::Settings.from(options, root:), name: "engine")
  #   Log.logger.info("started", plan: "003.00")
  module Log
    # Where both processes log unless `--log` says otherwise, relative to the
    # project root.
    DEFAULT_FILE = File.join("log", "development.log")

    # `--log -`: the log goes to STDOUT instead of a file.
    STDOUT_FILE = "-"

    # Lowest first. Anything below the chosen level is not written.
    LEVELS = %w[debug info warn error fatal].freeze

    # The level a run logs at when nothing says otherwise.
    DEFAULT_LEVEL = "info"

    # `--log-format` to SemanticLogger's formatter. `standard` is the one-line
    # formatter rather than the default one, which writes a stack trace over
    # many lines and breaks "one line per entry".
    FORMATS = { "standard" => :one_line, "json" => :json }.freeze

    # The format a run logs in when nothing says otherwise.
    DEFAULT_FORMAT = "standard"

    # How the engine tells the server it spawns where to log. The environment
    # rather than argv, for the same reason as the Redis URL: the server's
    # command line stays the same whatever the run was told.
    ENV_FILE = "OPENLANES_LOG"
    ENV_LEVEL = "OPENLANES_LOG_LEVEL"
    ENV_FORMAT = "OPENLANES_LOG_FORMAT"

    # The logger a process uses when {.setup} was never told its name.
    DEFAULT_NAME = "openlanes"

    # A level or format nobody knows. Raised before anything is opened, so a
    # typo is a refusal rather than a run that silently logs at the default.
    class Invalid < ArgumentError; end

    # Where a process logs, at what level, in which format.
    #
    # @!attribute [r] file
    #   @return [String] an absolute path, or {STDOUT_FILE}
    # @!attribute [r] level
    #   @return [String] one of {LEVELS}
    # @!attribute [r] format
    #   @return [String] one of the keys of {FORMATS}
    Settings = Data.define(:file, :level, :format) do
      # Flags first, then the environment the engine handed its server, then
      # the defaults. A relative file is taken from the project root, not the
      # directory the command was typed in, so `log/development.log` is the
      # same file for a run typed three directories down.
      #
      # @param options [Hash] the command's options: `:log`, `:log_level`, `:log_format`
      # @param root [String] the project root
      # @param env [Hash]
      # @return [Settings]
      # @raise [Invalid] for a level or format that is not one of the known ones
      def self.from(options = {}, root:, env: ENV)
        pick = ->(key, name) { [options[key], env[name]].map { it.to_s.strip }.find { !it.empty? } }
        file = pick.call(:log, ENV_FILE) || DEFAULT_FILE
        level = (pick.call(:log_level, ENV_LEVEL) || DEFAULT_LEVEL).downcase
        format = (pick.call(:log_format, ENV_FORMAT) || DEFAULT_FORMAT).downcase
        raise Invalid, "--log-level #{level}: use one of #{LEVELS.join(", ")}" unless LEVELS.include?(level)
        raise Invalid, "--log-format #{format}: use one of #{FORMATS.keys.join(", ")}" unless FORMATS.key?(format)

        file = File.expand_path(file, root) unless file == STDOUT_FILE
        new(file:, level:, format:)
      end

      # @return [Boolean] whether the log goes to STDOUT rather than a file
      def stdout? = file == STDOUT_FILE

      # @return [Hash{String => String}] for a child process's environment
      def env = { ENV_FILE => file, ENV_LEVEL => level, ENV_FORMAT => format }
    end

    class << self
      # The settings {.setup} was last given, nil before then.
      #
      # @return [Settings, nil]
      attr_reader :settings

      # Point SemanticLogger at the one file (or STDOUT), replacing whatever
      # it wrote to before, so calling this twice in one process (the suite
      # does) never leaves two appenders writing every line twice.
      #
      # @param settings [Settings]
      # @param name [String] what this process's lines are signed with,
      #   `engine` or `web`
      # @return [Settings]
      def setup(settings, name: DEFAULT_NAME)
        SemanticLogger.sync!
        SemanticLogger.clear_appenders!
        SemanticLogger.application = "openlanes"
        SemanticLogger.default_level = settings.level.to_sym
        formatter = FORMATS.fetch(settings.format)
        if settings.stdout?
          SemanticLogger.add_appender(io: $stdout, formatter:)
        else
          FileUtils.mkdir_p(File.dirname(settings.file))
          SemanticLogger.add_appender(file_name: settings.file, formatter:)
        end
        @name = name
        @settings = settings
      end

      # @return [Boolean] whether {.setup} has run in this process
      def configured? = !@settings.nil?

      # The file lines go to, or nil when they go nowhere or to STDOUT.
      #
      # @return [String, nil]
      def path = settings&.then { it.stdout? ? nil : it.file }

      # @param name [String, nil] another name than this process's own
      # @return [SemanticLogger::Logger]
      def logger(name = nil) = SemanticLogger[name || @name || DEFAULT_NAME]

      # One {UI.log} line, at +level+, with its fields as the payload. A
      # no-op until {.setup} has run: commands that never log (`list-plans`,
      # `docs`) still call code that reports through {UI.log}.
      #
      # @param message [String]
      # @param level [Symbol] one of {LEVELS}
      # @param fields [Hash] plan, status, agent, round, seconds and the like
      # @return [void]
      def event(message, level: :info, **fields)
        return unless configured?

        payload = fields.compact.transform_values { it.is_a?(Float) ? it.round(1) : it }
        logger.public_send(level, message.to_s, payload.empty? ? nil : payload)
      end

      # Forget the setup and stop writing. For the suite, which sets logging
      # up in a temp directory and must not leave an appender writing there.
      #
      # @return [void]
      def reset!
        SemanticLogger.clear_appenders!
        @settings = nil
        @name = nil
      end
    end
  end
end

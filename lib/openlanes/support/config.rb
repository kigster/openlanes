# frozen_string_literal: true

require "date"
require "yaml"

module OpenLanes
  # A project's `.openlanes.yml`, at its root:
  #
  #   project: Equilibris App   # heading for INDEX.md; default: the root's name
  #   lane: full                # default lane for `openlanes create`
  #   frontend: false           # a spec's `frontend:` when spec.md omits it
  #   jobs: 4                   # how many plans `openlanes run` works on at once
  #   redis_url: redis://10.0.4.2:6379/0  # the Redis the live run shares (W16)
  #   redis_outage_hours: 1     # how long agents stay paused for a lost Redis
  #                             # before the run shuts down (W32); any positive number
  #   desired_codebase_quality: high  # or mvp (R4): what a review that is ok but
  #                             # not perfect does, and M5's column of defaults
  #   merge:
  #     by: human               # who merges a reviewed PR (M4); `openlanes start` watches it
  #     max_rejections: 2       # rejections, hansolo's and chewie's together, before
  #                             # the plan stops going back to its builders (M6)
  #   commands:                 # per-command option defaults
  #     run:
  #       timeout: 1800
  #   questions:
  #     model: anthropic/claude-haiku-5.5  # rewrites prose questions into choices (D9)
  #   review:
  #     max_hmm: 5              # most 🤔 a review may carry and be approved (R3);
  #                             # $OPENLANES_REVIEW_MAX_HMM beats it
  #   events:                   # the durable run log (plan 020.01), off by default
  #     enabled: true
  #     dir: /var/lib/openlanes/events  # default: under $XDG_STATE_HOME
  #   app:                      # how to run the app a plan builds (M12)
  #     kind: web
  #     processes:
  #       - name: web
  #         start: npx vite --port $PORT_WEB --strictPort
  #         ready: /
  #         preview: true
  #   coverage:                 # what the coverage gate measures (M15)
  #     command: bundle exec rspec
  #     report_command: jq '.total.lines.percent' coverage/coverage.json
  #     minimum: 95             # or report: + format: instead of report_command:
  #
  # Precedence, loudest first: a flag typed on the command line, the plan's
  # spec.md frontmatter, this file, the built-in default. The file supplies
  # defaults and nothing else.
  #
  # `jobs`, `lane` and `project` are each one command's option said once for
  # the whole project, so each has a second spelling under `commands:`.
  # Writing both is an error rather than a tie-break: two answers to one
  # question is a file somebody will edit in the wrong place.
  #
  # Anything unknown is an error naming the file, never a shrug: a config
  # silently ignored is a timeout somebody set that stops applying with no
  # signal anywhere.
  #
  # @!attribute [r] path
  #   @return [String, nil] the file, nil when the project has none
  # @!attribute [r] project
  #   @return [String, nil]
  # @!attribute [r] lane
  #   @return [Symbol, nil] one of {Plans::Spec::LANES}
  # @!attribute [r] frontend
  #   @return [Boolean, nil] nil when each plan decides
  # @!attribute [r] jobs
  #   @return [Integer, nil]
  # @!attribute [r] redis_url
  #   @return [String, nil] where the live run keeps its board, its commands
  #     and its plan claims; `--redis-url` beats it, and it beats `$REDIS_URL`
  # @!attribute [r] redis_outage_hours
  #   @return [Numeric, nil] `redis_outage_hours` as the file says it; read
  #     {#outage_limit}, which applies the default
  # @!attribute [r] commands
  #   @return [Hash{String => Hash{Symbol => Object}}] by command name, as
  #     typed: "run", "resync dirs"
  # @!attribute [r] merge_by
  #   @return [Symbol, nil] `merge.by`, one of {MERGERS}; nil reads as {#merger}'s default
  # @!attribute [r] merge_max_rejections
  #   @return [Integer, nil] `merge.max_rejections` as the file says it; read
  #     {#max_rejections}, which applies the default
  # @!attribute [r] app
  #   @return [OpenLanes::Apps::Definition, nil] the processes `openlanes app
  #     start` runs; nil when the project declares none, and then nothing
  #     about apps happens anywhere
  # @!attribute [r] aging_since
  #   @return [Date, nil] `plans.aging_since`: no blocked plan ages from
  #     before it, so weeks the project sat paused do not count; nil is no floor
  # @!attribute [r] questions_model
  #   @return [String, nil] `questions.model`: the OpenRouter model that
  #     rewrites a prose question into lettered choices; nil takes
  #     {Live::ChoiceConverter::DEFAULT_MODEL}
  # @!attribute [r] review_max_hmm
  #   @return [Integer, nil] `review.max_hmm` as the file says it; read
  #     {#max_hmm}, which applies the environment and the default
  # @!attribute [r] desired_codebase_quality
  #   @return [Symbol, nil] one of {QUALITIES}, as the file says it; nil
  #     while the project is still to be asked (R4)
  # @!attribute [r] coverage
  #   @return [OpenLanes::Coverage::Config, nil] the `coverage:` section; nil
  #     when the project declares none, and then the gate sends the pull
  #     request back to its builder to write one
  # @!attribute [r] events_enabled
  #   @return [Boolean] `events.enabled`: whether runs append to the event log
  # @!attribute [r] events_dir
  #   @return [String, nil] `events.dir`: an absolute path; nil takes
  #     {Events::Location}'s default
  Config = Data.define(:path,
    :project,
    :lane,
    :frontend,
    :jobs,
    :redis_url,
    :redis_outage_hours,
    :commands,
    :merge_by,
    :app,
    :aging_since,
    :questions_model,
    :review_max_hmm,
    :merge_max_rejections,
    :desired_codebase_quality,
    :coverage,
    :events_enabled,
    :events_dir) do
    def initialize(path: nil, project: nil, lane: nil, frontend: nil, jobs: nil, redis_url: nil,
      redis_outage_hours: nil, commands: {}, merge_by: nil, app: nil, aging_since: nil, questions_model: nil, review_max_hmm: nil, merge_max_rejections: nil,
      desired_codebase_quality: nil, coverage: nil, events_enabled: false, events_dir: nil)
      super
    end

    # How many times a plan's pull request may be rejected, by hansolo and
    # chewie counted together, before it stops going back to its builders
    # (M6). `merge.max_rejections` when the file says it, otherwise M5's
    # column for `desired_codebase_quality:` (R4); two, `high`'s, when neither is set.
    #
    # @return [Integer]
    def max_rejections
      merge_max_rejections || Config::MAX_REJECTIONS_BY_QUALITY.fetch(desired_codebase_quality, Config::DEFAULT_MAX_REJECTIONS)
    end

    # @return [Boolean] whether the file has no `desired_codebase_quality:`,
    #   and so the person is still to be asked (R4)
    def quality_unset? = desired_codebase_quality.nil?

    # Seconds a run keeps its agents paused for a Redis that stopped
    # answering before it gives up and shuts down (W32): an hour, unless
    # `redis_outage_hours` says otherwise.
    #
    # @return [Float]
    def outage_limit = (redis_outage_hours || Config::DEFAULT_OUTAGE_HOURS) * 3600.0

    # The most 🤔 a review may carry and still be `review-approved` (R3).
    # Loudest first: `$OPENLANES_REVIEW_MAX_HMM`, then `review.max_hmm`, then
    # {Plans::Verdict::DEFAULT_MAX_HMM}. The variable is there so one run can
    # be stricter or looser without editing a file the whole team shares.
    #
    # @param env [Hash] the environment, injectable for tests
    # @return [Integer]
    # @raise [OpenLanes::Error] when the variable is not a whole number
    def max_hmm(env: ENV)
      raw = env[Config::MAX_HMM_ENV].to_s.strip
      return review_max_hmm || Plans::Verdict::DEFAULT_MAX_HMM if raw.empty?
      return Integer(raw, 10) if raw.match?(/\A\d+\z/)

      raise Error, "#{Config::MAX_HMM_ENV}=#{raw.inspect} is not a whole number"
    end

    # Who merges a pull request once its review passed (M4). A person, unless
    # the file says otherwise, since merging is the one thing no agent may do.
    #
    # @return [Symbol] `:human` or `:auto`
    def merger = merge_by || Config::MERGERS.first

    # @return [Boolean] whether the engine waits on a person to merge, and so
    #   watches the pull requests it opened
    def human_merges? = merger == :human

    # One command's option defaults, the top-level spelling folded in.
    #
    # @param command [String, Symbol] e.g. :run or "resync dirs"
    # @return [Hash{Symbol => Object}]
    def for(command)
      name = command.to_s
      folded = Config::SHORTHANDS.filter_map { |key, owner|
        value = public_send(key)
        [key, value.is_a?(Symbol) ? value.to_s : value] if owner == name && !value.nil?
      }.to_h
      commands.fetch(name, {}).merge(folded)
    end

    # @return [Boolean] whether the project has a file at all
    def file? = !path.nil?

    # The file `openlanes init` writes: only what was set, in the order the
    # keys are documented, so it reads like the example it came from.
    #
    # @return [String]
    def to_yaml
      settings = { "project" => project, "lane" => lane&.to_s, "frontend" => frontend, "jobs" => jobs,
                   "redis_url" => redis_url, "redis_outage_hours" => redis_outage_hours,
                   "desired_codebase_quality" => desired_codebase_quality&.to_s, "merge" => merge_settings }
      settings["commands"] = commands.transform_values { it.transform_keys(&:to_s) } unless commands.empty?
      settings["app"] = app.to_h if app
      settings["plans"] = { "aging_since" => aging_since.iso8601 } if aging_since
      settings["questions"] = { "model" => questions_model } if questions_model
      settings["review"] = { "max_hmm" => review_max_hmm } if review_max_hmm
      settings["coverage"] = coverage.to_h if coverage
      settings["events"] = { "enabled" => events_enabled, "dir" => events_dir }.compact if events_enabled || events_dir
      YAML.dump(settings.compact).delete_prefix("---\n")
    end

    private

    # @return [Hash, nil] `merge:` as the file would hold it, nil when nothing is set
    def merge_settings
      merge = { "by" => merge_by&.to_s, "max_rejections" => merge_max_rejections }.compact
      merge.empty? ? nil : merge
    end
  end

  class Config
    # The file, at the project root.
    FILE = Project::FILE

    # Every key the top level may hold.
    KEYS = %w[project lane frontend jobs redis_url redis_outage_hours desired_codebase_quality merge commands app plans
              questions review coverage events].freeze

    # What `desired_codebase_quality:` may say (R4), the default first. M5's
    # `top_notch` and `medium` were dropped.
    QUALITIES = %i[high mvp].freeze

    # Who may merge, the default first.
    MERGERS = %i[human auto].freeze

    # Every key `merge:` may hold.
    MERGE_KEYS = %w[by max_rejections].freeze

    # {#max_rejections} when the file names none (M6).
    DEFAULT_MAX_REJECTIONS = 2

    # M5's `max_rejections` row, for the two columns R4 kept.
    MAX_REJECTIONS_BY_QUALITY = { high: 2, mvp: 1 }.freeze

    # {#outage_limit} when the file names none (W32).
    DEFAULT_OUTAGE_HOURS = 1

    # Every key `plans:` may hold. Checked key by key, like the top level.
    PLAN_KEYS = %w[aging_since].freeze

    # Every key `questions:` may hold.
    QUESTION_KEYS = %w[model].freeze

    # Every key `review:` may hold.
    REVIEW_KEYS = %w[max_hmm].freeze

    # The variable that beats `review.max_hmm`.
    MAX_HMM_ENV = "OPENLANES_REVIEW_MAX_HMM"

    # Every key `events:` may hold.
    EVENT_KEYS = %w[enabled dir].freeze

    # Schemes a `redis_url:` may use.
    REDIS_SCHEMES = %w[redis rediss unix].freeze

    # Top-level keys that are one command's option, by the command that takes it.
    SHORTHANDS = { project: "index", lane: "create", jobs: "run" }.freeze

    class << self
      # @param root [String] the project root
      # @return [OpenLanes::Config] empty when the root holds no file
      # @raise [OpenLanes::Error] when the file exists and cannot be used
      def load(root)
        path = File.join(root, FILE)
        return new unless File.file?(path)

        parse(File.read(path, encoding: "UTF-8"), path:)
      end

      # The project the process is working in. {CLI::Base} has already moved
      # to the root, so that is where this looks; the file is reread only
      # when it changes, because routing asks for it on every tick.
      #
      # @return [OpenLanes::Config]
      def current
        root = Project.root || Dir.pwd
        path = File.join(root, FILE)
        key = [path, File.file?(path) && File.mtime(path)]
        return @current.last if @current&.first == key

        load(root).tap { |config| @current = [key, config] }
      end

      # @param text [String] the whole file
      # @param path [String] for every error message
      # @return [OpenLanes::Config]
      def parse(text, path:)
        data = YAML.safe_load(text, permitted_classes: [Date]) || {}
        fail_with(path, "expected a mapping of settings at the top") unless data.is_a?(Hash)

        settings = data.transform_keys(&:to_s)
        unknown = settings.keys - KEYS
        unless unknown.empty?
          fail_with(path,
            "unknown key#{"s" unless unknown.size == 1} #{unknown.join(", ")}; " \
            "known: #{KEYS.join(", ")}")
        end

        config = new(path:,
          project:   project(settings, path),
          lane:      lane(settings, path),
          frontend:  frontend(settings, path),
          jobs:      jobs(settings, path),
          redis_url: redis_url(settings, path),
          redis_outage_hours: redis_outage_hours(settings, path),
          desired_codebase_quality: quality(settings, path),
          **merge(settings["merge"], path),
          commands:  commands(settings["commands"], path),
          app:       settings.key?("app") ? Apps::Definition.parse(settings["app"], path:) : nil,
          **plans(settings["plans"], path),
          **questions(settings["questions"], path),
          **review(settings["review"], path),
          coverage:  settings.key?("coverage") ? Coverage::Config.parse(settings["coverage"], path:) : nil,
          **events(settings["events"], path))
        conflicts!(config, path)
        config
      rescue Psych::Exception => e
        fail_with(path, "is not valid YAML (#{e.message.lines.first.to_s.strip})")
      end

      private

      # @return [void] never returns
      def fail_with(path, message) = raise(Error, "#{path}: #{message}")

      # @return [String, nil]
      def project(settings, path)
        value = settings["project"]
        return nil if value.nil?
        return value.strip if value.is_a?(String) && !value.strip.empty?

        fail_with(path, "project: must be a non-empty name, not #{value.inspect}")
      end

      # @return [Symbol, nil]
      def lane(settings, path)
        return nil unless settings.key?("lane")

        value = settings["lane"].to_s.strip.downcase.to_sym
        return value if Plans::Spec::LANES.include?(value)

        fail_with(path, "lane: #{settings["lane"].inspect} is not one of #{Plans::Spec::LANES.join(", ")}")
      end

      # @return [Boolean, nil]
      def frontend(settings, path)
        value = settings["frontend"]
        return value if [true, false, nil].include?(value)

        fail_with(path, "frontend: #{value.inspect} is not true or false")
      end

      # @return [Integer, nil]
      def jobs(settings, path)
        value = settings["jobs"]
        return value if value.nil? || (value.is_a?(Integer) && value.positive?)

        fail_with(path, "jobs: #{value.inspect} is not a whole number above zero")
      end

      # @return [String, nil]
      def redis_url(settings, path)
        value = settings["redis_url"]
        return nil if value.nil?
        return value.strip if value.is_a?(String) && REDIS_SCHEMES.include?(value.strip[/\A([a-z]+):/, 1])

        fail_with(path, "redis_url: #{value.inspect} is not a #{REDIS_SCHEMES.map { "#{it}://" }.join(", ")} URL")
      end

      # Any positive number: half an hour is `0.5`.
      #
      # @return [Numeric, nil]
      def redis_outage_hours(settings, path)
        value = settings["redis_outage_hours"]
        return value if value.nil? || (value.is_a?(Numeric) && value.positive?)

        fail_with(path, "redis_outage_hours: #{value.inspect} is not a number of hours above zero")
      end

      # @return [Symbol, nil]
      def quality(settings, path)
        return nil unless settings.key?("desired_codebase_quality")

        value = settings["desired_codebase_quality"].to_s.strip.downcase.to_sym
        return value if QUALITIES.include?(value)

        fail_with(path, "desired_codebase_quality: #{settings["desired_codebase_quality"].inspect} is not one of #{QUALITIES.join(", ")}")
      end

      # @return [Hash{Symbol => Object}] the `merge:` settings, as keywords for {Config.new}
      def merge(value, path)
        return {} if value.nil?

        fail_with(path, "merge: must be a mapping, e.g. `merge: { by: human }`") unless value.is_a?(Hash)

        settings = value.transform_keys(&:to_s)
        unknown = settings.keys - MERGE_KEYS
        fail_with(path, "merge: unknown key #{unknown.join(", ")}; known: #{MERGE_KEYS.join(", ")}") unless unknown.empty?

        { merge_by: merge_by(settings, path), merge_max_rejections: max_rejections(settings, path) }.compact
      end

      # @return [Symbol, nil]
      def merge_by(settings, path)
        return nil unless settings.key?("by")

        by = settings["by"].to_s.strip.downcase.to_sym
        return by if MERGERS.include?(by)

        fail_with(path, "merge.by: #{settings["by"].inspect} is not one of #{MERGERS.join(", ")}")
      end

      # @return [Integer, nil]
      def max_rejections(settings, path)
        max = settings["max_rejections"]
        return max if max.nil? || (max.is_a?(Integer) && max.positive?)

        fail_with(path, "merge.max_rejections: #{max.inspect} is not a whole number above zero")
      end

      # @return [Hash{String => Hash{Symbol => Object}}]
      def commands(value, path)
        return {} if value.nil?

        fail_with(path, "commands: must be a mapping of command name to its options") unless value.is_a?(Hash)

        value.to_h do |name, options|
          fail_with(path, "commands.#{name}: must be a mapping of option to value") unless options.is_a?(Hash)

          [name.to_s.strip, options.transform_keys { it.to_s.tr("-", "_").to_sym }]
        end
      end

      # @return [Hash{Symbol => Object}] the `plans:` settings, as keywords for {Config.new}
      def plans(value, path)
        return {} if value.nil?

        fail_with(path, "plans: must be a mapping of setting to value") unless value.is_a?(Hash)

        settings = value.transform_keys(&:to_s)
        (settings.keys - PLAN_KEYS).each do |key|
          fail_with(path, "plans.#{key}: unknown key; known: #{PLAN_KEYS.join(", ")}")
        end
        { aging_since: aging_since(settings["aging_since"], path) }
      end

      # @return [Hash{Symbol => Object}] the `questions:` settings, as keywords for {Config.new}
      def questions(value, path)
        return {} if value.nil?

        fail_with(path, "questions: must be a mapping of setting to value") unless value.is_a?(Hash)

        settings = value.transform_keys(&:to_s)
        (settings.keys - QUESTION_KEYS).each do |key|
          fail_with(path, "questions.#{key}: unknown key; known: #{QUESTION_KEYS.join(", ")}")
        end
        model = settings["model"]
        return {} if model.nil?
        return { questions_model: model.strip } if model.is_a?(String) && !model.strip.empty?

        fail_with(path, "questions.model: #{model.inspect} is not a model id, e.g. #{Live::ChoiceConverter::DEFAULT_MODEL}")
      end

      # @return [Hash{Symbol => Object}] the `review:` settings, as keywords for {Config.new}
      def review(value, path)
        return {} if value.nil?

        fail_with(path, "review: must be a mapping of setting to value") unless value.is_a?(Hash)

        settings = value.transform_keys(&:to_s)
        (settings.keys - REVIEW_KEYS).each do |key|
          fail_with(path, "review.#{key}: unknown key; known: #{REVIEW_KEYS.join(", ")}")
        end
        max = settings["max_hmm"]
        return {} if max.nil?
        return { review_max_hmm: max } if max.is_a?(Integer) && !max.negative?

        fail_with(path, "review.max_hmm: #{max.inspect} is not a whole number")
      end

      # @return [Hash{Symbol => Object}] the `events:` settings, as keywords for {Config.new}
      def events(value, path)
        return {} if value.nil?

        fail_with(path, "events: must be a mapping, e.g. `events: { enabled: true }`") unless value.is_a?(Hash)

        settings = value.transform_keys(&:to_s)
        (settings.keys - EVENT_KEYS).each do |key|
          fail_with(path, "events.#{key}: unknown key; known: #{EVENT_KEYS.join(", ")}")
        end
        enabled = settings.fetch("enabled", false)
        fail_with(path, "events.enabled: #{enabled.inspect} is not true or false") unless [true, false].include?(enabled)

        { events_enabled: enabled, events_dir: events_dir(settings["dir"], path) }
      end

      # A relative directory would land wherever the command was started,
      # which is a different log per shell; so only an absolute one is taken.
      #
      # @return [String, nil]
      def events_dir(value, path)
        return nil if value.nil?
        return File.expand_path(value.strip) if value.is_a?(String) && value.strip.match?(%r{\A[/~]})

        fail_with(path, "events.dir: #{value.inspect} is not an absolute path")
      end

      # YAML hands an unquoted `2026-10-01` over as a Date already, and a
      # quoted one as a String; both are the same day to whoever typed it.
      #
      # @return [Date, nil]
      def aging_since(value, path)
        return value if value.nil? || value.instance_of?(Date)

        Date.iso8601(value.to_s)
      rescue Date::Error
        fail_with(path, "plans.aging_since: #{value.inspect} is not a date (YYYY-MM-DD)")
      end

      # @return [void]
      def conflicts!(config, path)
        SHORTHANDS.each do |key, owner|
          next if config.public_send(key).nil? || !config.commands.fetch(owner, {}).key?(key)

          fail_with(path, "#{key} and commands.#{owner}.#{key} are the same setting; keep one")
        end
      end
    end
  end
end

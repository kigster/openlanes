# frozen_string_literal: true

require "date"
require "yaml"

module OpenLanes
  # A project's `.openlanes/config.yml`, at its root:
  #
  #   project: Equilibris App   # heading for INDEX.md; default: the root's name
  #   starts: research          # default for `openlanes create`: one of Spec::STARTS
  #   frontend: false           # a spec's `frontend:` when spec.md omits it
  #   jobs: 4                   # how many plans `openlanes run` works on at once
  #   adapter: codex            # the coding agent for every agent that names none (plan 040)
  #   redis_url: redis://10.0.4.2:6379/0  # the Redis the live run shares (W16)
  #   redis_outage_hours: 1     # how long agents stay paused for a lost Redis
  #                             # before the run shuts down (W32); any positive number
  #   redis_backoff:            # how a lost Redis is asked again (plan 022)
  #     initial: 1              # seconds; the Fibonacci gaps are its multiples
  #     cap: 30                 # seconds, the longest gap between two asks
  #     jitter: true            # full jitter: each gap drawn from [0, gap)
  #   ci_pending_hours: 4       # how long CI may stay pending after verification
  #                             # before the plan is surfaced to a person; any positive number
  #   desired_codebase_quality: high  # standard or mvp (R4): what a review that is ok but
  #                             # not perfect does, and M5's column of defaults
  #   review:
  #     adapters: [claude, codex, gemini]  # the coding agents the reviewers are dealt
  #                             # across, main one first (plan 031, V7); unset: `adapter:`
  #   merge:
  #     by: human               # who merges a reviewed PR (M4); `openlanes start` watches it
  #     max_rejections: 2       # rejections, staff-reviewer's and verifier's together, before
  #                             # the plan stops going back to its builders (M6)
  #   ci:                       # what checks a pull request (M21); `openlanes init` settles it
  #     provider: github_actions
  #     config: .github/workflows/ci.yml
  #   stack:                    # the project's stack, also written to docs/decisions/stack.md
  #     language: ruby
  #     frameworks: [rails]
  #   commands:                 # per-command option defaults
  #     run:
  #       timeout: 1800
  #   questions:
  #     model: anthropic/claude-haiku-5.5  # rewrites prose questions into choices (D9)
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
  # `jobs`, `starts` and `project` are each one command's option said once for
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
  # @!attribute [r] starts
  #   @return [Symbol, nil] one of {Plans::Spec::STARTS}
  # @!attribute [r] frontend
  #   @return [Boolean, nil] nil when each plan decides
  # @!attribute [r] jobs
  #   @return [Integer, nil]
  # @!attribute [r] adapter
  #   @return [String, nil] one of {Adapters.names}: what an agent runs on when
  #     neither the plan nor its own frontmatter names one; nil is
  #     {Adapters::DEFAULT}
  # @!attribute [r] redis_url
  #   @return [String, nil] where the live run keeps its board, its commands
  #     and its plan claims; `--redis-url` beats it, and it beats `$REDIS_URL`
  # @!attribute [r] redis_outage_hours
  #   @return [Numeric, nil] `redis_outage_hours` as the file says it; read
  #     {#outage_limit}, which applies the default
  # @!attribute [r] ci_pending_hours
  #   @return [Numeric, nil] `ci_pending_hours` as the file says it; read
  #     {#ci_pending_limit}, which applies the default
  # @!attribute [r] redis_backoff
  #   @return [Hash{Symbol => Object}] `redis_backoff:` as typed, keyed
  #     :initial, :cap, :jitter; {Live::Outage} applies the defaults
  # @!attribute [r] commands
  #   @return [Hash{String => Hash{Symbol => Object}}] by command name, as
  #     typed: "run", "resync dirs"
  # @!attribute [r] review_adapters
  #   @return [Array<String>] `review.adapters`: the coding agents
  #     {Agents::Dealing} deals the reviewers across, main one first; empty
  #     when unset, and then every reviewer runs on {#adapter}
  # @!attribute [r] merge_by
  #   @return [Symbol, nil] `merge.by`, one of {MERGERS}; nil reads as {#merger}'s default
  # @!attribute [r] merge_max_rejections
  #   @return [Integer, nil] `merge.max_rejections` as the file says it; read
  #     {#max_rejections}, which applies the default
  # @!attribute [r] ci
  #   @return [Hash{Symbol => Object}, nil] `{provider:, config:}`, provider one of {CI_PROVIDERS}
  # @!attribute [r] stack
  #   @return [Hash{Symbol => Object}, nil] only the {STACK_FIELDS} that were answered;
  #     `frameworks` is an Array, every other field a String
  # @!attribute [r] architecture_decisions
  #   @return [OpenLanes::Setup::ArchitectureDecisions, nil] what the repository
  #     holds now and what is wanted; a file with this has no `ci:` or `stack:`,
  #     which only an older file holds
  # @!attribute [r] app
  #   @return [OpenLanes::Apps::Definition, nil] the processes `openlanes project
  #     start` runs; nil when the project declares none, and then nothing
  #     about apps happens anywhere
  # @!attribute [r] aging_since
  #   @return [Date, nil] `plans.aging_since`: no blocked plan ages from
  #     before it, so weeks the project sat paused do not count; nil is no floor
  # @!attribute [r] questions_model
  #   @return [String, nil] `questions.model`: the OpenRouter model that
  #     rewrites a prose question into lettered choices; nil takes
  #     {Live::ChoiceConverter::DEFAULT_MODEL}
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
  # @!attribute [r] budget_plan_usd
  #   @return [Float, nil] `budget.plan_usd`: the most a plan may spend, in
  #     estimated dollars, before no new round starts on it; nil is no cap.
  #     Read through {Events::PlanSpend.cap_for}, the one place that asks
  Config = Data.define(:path,
    :project,
    :starts,
    :frontend,
    :jobs,
    :adapter,
    :redis_url,
    :redis_outage_hours,
    :ci_pending_hours,
    :redis_backoff,
    :commands,
    :merge_by,
    :app,
    :aging_since,
    :questions_model,
    :merge_max_rejections,
    :desired_codebase_quality,
    :coverage,
    :ci,
    :stack,
    :architecture_decisions,
    :events_enabled,
    :events_dir,
    :review_adapters,
    :refactor_threshold,
    :refactor_lock_hours,
    :chime,
    :budget_plan_usd) do
    def initialize(path: nil, project: nil, starts: nil, frontend: nil, jobs: nil, adapter: nil, redis_url: nil,
      redis_outage_hours: nil, ci_pending_hours: nil, redis_backoff: {}, commands: {}, merge_by: nil, app: nil, aging_since: nil, questions_model: nil, merge_max_rejections: nil,
      desired_codebase_quality: nil, coverage: nil, ci: nil, stack: nil, architecture_decisions: nil, events_enabled: false, events_dir: nil, review_adapters: [], refactor_threshold: nil, refactor_lock_hours: nil, chime: nil, budget_plan_usd: nil) # rubocop:disable Naming/MethodParameterName
      super
    end

    # Whether the control room dings when a question arrives: `chime:`, on
    # unless the file says `false`. The page's checkbox writes it.
    #
    # @return [Boolean]
    def chime? = chime != false

    # The share of the codebase, in percent by files or by lines, above
    # which a refactor runs alone (R6): `refactor.threshold`, else 50.
    #
    # @return [Integer]
    def refactor_percent = refactor_threshold || Plans::Execution::DEFAULT_THRESHOLD

    # How long a refactor's global lock holds before it lapses and other
    # plans may start beside it (R6): `refactor.lock_hours`, else 24.
    #
    # @return [Integer] seconds
    def refactor_lock_seconds = ((refactor_lock_hours || Plans::GlobalLock::DEFAULT_HOURS) * 3600).round

    # How many times a plan's pull request may be rejected, by staff-reviewer and
    # verifier counted together, before it stops going back to its builders
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

    # Seconds CI may stay pending on a verified pull request before the plan
    # is surfaced to a person rather than waited on in silence (issue #175):
    # four hours, unless `ci_pending_hours` says otherwise.
    #
    # @return [Float]
    def ci_pending_limit = (ci_pending_hours || Config::DEFAULT_CI_PENDING_HOURS) * 3600.0

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

    # The file `openlanes init` writes: every key the schema knows, in the
    # order it documents them, unset ones as their default (most of them
    # empty). A person editing it sees every setting there is, and
    # {Config.parse} reads an empty one as unset, so the file parses back to
    # this same Config.
    #
    # @return [String]
    def to_yaml = YAML.dump(Config.fill(Config::Schema.defaults, to_settings)).delete_prefix("---\n")

    # What {#to_yaml} writes, as a Hash with string keys: the values as the
    # parser normalised them, which is what {Config.parse} checks against
    # the schema.
    #
    # @return [Hash{String => Object}]
    def to_settings
      settings = { "project" => project, "starts" => starts&.to_s, "frontend" => frontend, "jobs" => jobs,
                   "adapter" => adapter, "redis_url" => redis_url, "redis_outage_hours" => redis_outage_hours,
                   "ci_pending_hours" => ci_pending_hours,
                   "redis_backoff" => (redis_backoff.transform_keys(&:to_s) unless redis_backoff.empty?),
                   "desired_codebase_quality" => desired_codebase_quality&.to_s, "merge" => merge_settings,
                   "ci" => ci && { "provider" => ci[:provider].to_s, "config" => ci[:config] }.compact,
                   "stack" => stack&.transform_keys(&:to_s),
                   "architecture_decisions" => architecture_decisions&.to_file }
      settings["commands"] = commands.transform_values { it.transform_keys(&:to_s) } unless commands.empty?
      settings["app"] = app.to_h if app
      settings["plans"] = { "aging_since" => aging_since.iso8601 } if aging_since
      settings["questions"] = { "model" => questions_model } if questions_model
      settings["coverage"] = coverage.to_h if coverage
      settings["events"] = { "enabled" => events_enabled, "dir" => events_dir }.compact if events_enabled || events_dir
      settings["review"] = { "adapters" => review_adapters } unless review_adapters.empty?
      refactor = { "threshold" => refactor_threshold, "lock_hours" => refactor_lock_hours }.compact
      settings["refactor"] = refactor unless refactor.empty?
      settings["budget"] = { "plan_usd" => budget_plan_usd } if budget_plan_usd
      settings["chime"] = chime unless chime.nil?
      settings.compact
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

    # Every key the top level may hold. This and every key list below is
    # read from the schema, so the schema and the parser cannot disagree.
    KEYS = Schema.keys.freeze

    # What `desired_codebase_quality:` may say (R4, plan 035), the strictest first. M5's
    # `top_notch` and `medium` were dropped.
    QUALITIES = Schema.enum_for("desired_codebase_quality").map(&:to_sym).freeze

    # Who may merge, the default first.
    MERGERS = Schema.enum_for("merge", "by").map(&:to_sym).freeze

    # Every key `review:` may hold.
    REVIEW_KEYS = Schema.keys_for("review").freeze

    # Every key `merge:` may hold.
    MERGE_KEYS = Schema.keys_for("merge").freeze

    # {#max_rejections} when the file names none (M6).
    DEFAULT_MAX_REJECTIONS = 2

    # M5's `max_rejections` row, one column per quality.
    MAX_REJECTIONS_BY_QUALITY = { high: 2, standard: 2, mvp: 1 }.freeze

    # {#outage_limit} when the file names none (W32).
    DEFAULT_OUTAGE_HOURS = 1

    # {#ci_pending_limit} when the file names none: longer than any healthy
    # run, short enough that a stuck runner is noticed the same working day.
    DEFAULT_CI_PENDING_HOURS = 4

    # Every key `redis_backoff:` may hold.
    BACKOFF_KEYS = Schema.keys_for("redis_backoff").freeze

    # Every key `plans:` may hold. Checked key by key, like the top level.
    PLAN_KEYS = Schema.keys_for("plans").freeze

    # Every key `questions:` may hold.
    QUESTION_KEYS = Schema.keys_for("questions").freeze

    # What may check a pull request (M21). `external` is a CI openlanes does
    # not scaffold; `none` is a decision, not a missing answer.
    CI_PROVIDERS = %i[github_actions circleci jenkins external none].freeze

    # What `stack:` may hold. `from` and `to` are set when a port is planned.
    STACK_FIELDS = Schema.keys_for("stack").map(&:to_sym).freeze

    # The one stack field that is a list.
    STACK_LISTS = %i[frameworks].freeze

    # Every key `events:` may hold.
    EVENT_KEYS = Schema.keys_for("events").freeze

    # Every key `refactor:` may hold.
    REFACTOR_KEYS = Schema.keys_for("refactor").freeze

    # Every key `budget:` may hold.
    BUDGET_KEYS = Schema.keys_for("budget").freeze

    # Schemes a `redis_url:` may use.
    REDIS_SCHEMES = %w[redis rediss unix].freeze

    # Top-level keys that are one command's option, by the command that takes it.
    SHORTHANDS = { project: "index", starts: "create", jobs: "run" }.freeze

    class << self
      # @param root [String] the project root
      # @return [OpenLanes::Config] empty when the root holds no file
      # @raise [OpenLanes::Error] when the file exists and cannot be used
      def load(root)
        path = Project.config_path(root)
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
        path = Project.config_path(root)
        key = [path, File.file?(path) && File.mtime(path)]
        return @current.last if @current&.first == key

        load(root).tap { |config| @current = [key, config] }
      end

      # Set one top-level true/false key in the project's file, in place: the
      # line is rewritten where it stands, or added at the end, and every
      # comment and every other key is left exactly as a person wrote it.
      # A dump of the parsed file would drop the comments.
      #
      # @param root [String] the project root
      # @param key [String] one of {KEYS}
      # @param value [Boolean]
      # @return [String] the file's path
      def write_flag(root, key, value)
        path = Project.config_path(root)
        FileUtils.mkdir_p(File.dirname(path))
        text = File.file?(path) ? File.read(path, encoding: "UTF-8") : ""
        line = "#{key}: #{value}"
        if text.match?(/^#{Regexp.escape(key)}:.*$/)
          text = text.sub(/^#{Regexp.escape(key)}:.*$/, line)
        else
          text += "\n" unless text.empty? || text.end_with?("\n")
          text += "#{line}\n"
        end
        File.write(path, text)
        path
      end

      # @param text [String] the whole file
      # @param path [String] for every error message
      # @return [OpenLanes::Config]
      def parse(text, path:)
        data = YAML.safe_load(text, permitted_classes: [Date]) || {}
        fail_with(path, "expected a mapping of settings at the top") unless data.is_a?(Hash)

        settings = unset_dropped(data.transform_keys(&:to_s))
        Secrets.refuse!(settings, path)
        unknown = settings.keys - KEYS
        unless unknown.empty?
          fail_with(path,
            "unknown key#{"s" unless unknown.size == 1} #{unknown.join(", ")}; " \
            "known: #{KEYS.join(", ")}")
        end

        config = new(path:,
          project:   project(settings, path),
          starts:    starts_at(settings, path),
          frontend:  frontend(settings, path),
          jobs:      jobs(settings, path),
          adapter:   adapter(settings, path),
          redis_url: redis_url(settings, path),
          redis_outage_hours: hours(settings, "redis_outage_hours", path),
          ci_pending_hours: hours(settings, "ci_pending_hours", path),
          redis_backoff: redis_backoff(settings["redis_backoff"], path),
          desired_codebase_quality: quality(settings, path),
          **merge(settings["merge"], path),
          **review(settings["review"], path),
          ci:        ci(settings["ci"], path),
          stack:     stack(settings["stack"], path),
          architecture_decisions: Setup::ArchitectureDecisions.parse(settings["architecture_decisions"], path:),
          commands:  commands(settings["commands"], path),
          app:       settings.key?("app") ? Apps::Definition.parse(settings["app"], path:) : nil,
          **plans(settings["plans"], path),
          **questions(settings["questions"], path),
          coverage:  settings.key?("coverage") ? Coverage::Config.parse(settings["coverage"], path:) : nil,
          **events(settings["events"], path),
          **refactor(settings["refactor"], path),
          chime:     chime(settings, path),
          **budget(settings["budget"], path))
        conflicts!(config, path)
        schema!(config.to_settings.except("commands"), path)
        config
      rescue Psych::Exception => e
        fail_with(path, "is not valid YAML (#{e.message.lines.first.to_s.strip})")
      end

      # A full file's settings laid over the defaults, key by key: the
      # defaults give the order and the empty slots, the settings the values.
      #
      # @param defaults [Hash{String => Object}] {Schema.defaults}
      # @param settings [Hash{String => Object}] {#to_settings}
      # @return [Hash{String => Object}]
      def fill(defaults, settings)
        defaults.merge(settings) { |_, default, value| default.is_a?(Hash) && value.is_a?(Hash) ? default.merge(value) : value }
      end

      private

      # An empty value means unset, as if the key were not there, and a
      # mapping whose every value is empty is left out with it. That is what
      # lets {#to_yaml} write every key: `starts:` with nothing after it is
      # the same file as no `starts:` at all. A mapping written empty on
      # purpose (`app: {}`) is kept, so its own check still refuses it.
      #
      # @param settings [Hash{String => Object}]
      # @return [Hash{String => Object}]
      def unset_dropped(settings)
        settings.each_with_object({}) do |(key, value), kept|
          next if value.nil?

          # A section the schema leaves open (`app`, `coverage`, ...) is
          # passed whole to its own parser, which decides what an empty value
          # inside it means.
          if value.is_a?(Hash) && !value.empty? && !Schema.keys_for(key).empty?
            inner = value.compact
            kept[key] = inner unless inner.empty?
          else
            kept[key] = value
          end
        end
      end

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
      def starts_at(settings, path)
        return nil unless settings.key?("starts")

        value = settings["starts"].to_s.strip.downcase.to_sym
        return value if Plans::Spec::STARTS.include?(value)

        fail_with(path, "starts: #{settings["starts"].inspect} is not one of #{Plans::Spec::STARTS.join(", ")}")
      end

      # @return [Boolean, nil]
      def frontend(settings, path)
        value = settings["frontend"]
        return value if [true, false, nil].include?(value)

        fail_with(path, "frontend: #{value.inspect} is not true or false")
      end

      # @return [Boolean, nil]
      def chime(settings, path)
        value = settings["chime"]
        return value if [true, false, nil].include?(value)

        fail_with(path, "chime: #{value.inspect} is not true or false")
      end

      # @return [Integer, nil]
      def jobs(settings, path)
        value = settings["jobs"]
        return value if value.nil? || (value.is_a?(Integer) && value.positive?)

        fail_with(path, "jobs: #{value.inspect} is not a whole number above zero")
      end

      # @return [String, nil]
      def adapter(settings, path)
        value = settings["adapter"]
        return nil if value.nil?
        return value.to_s if (value.is_a?(String) || value.is_a?(Symbol)) && Adapters.known?(value)

        fail_with(path, "adapter: #{value.inspect} is not one of #{Adapters.names.join(", ")}")
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
      # @param key [String] `redis_outage_hours` or `ci_pending_hours`
      # @return [Numeric, nil]
      def hours(settings, key, path)
        value = settings[key]
        return value if value.nil? || (value.is_a?(Numeric) && value.positive?)

        fail_with(path, "#{key}: #{value.inspect} is not a number of hours above zero")
      end

      # @return [Hash{Symbol => Object}] `redis_backoff:`, checked key by key
      def redis_backoff(value, path)
        return {} if value.nil?

        fail_with(path, "redis_backoff: must be a mapping of setting to value") unless value.is_a?(Hash)

        value.transform_keys(&:to_s).to_h do |key, setting|
          fail_with(path, "redis_backoff.#{key}: unknown key; known: #{BACKOFF_KEYS.join(", ")}") unless BACKOFF_KEYS.include?(key)
          if key == "jitter"
            fail_with(path, "redis_backoff.jitter: #{setting.inspect} is not true or false") unless [true, false].include?(setting)
          elsif !(setting.is_a?(Numeric) && setting.positive?)
            fail_with(path, "redis_backoff.#{key}: #{setting.inspect} is not a number of seconds above zero")
          end
          [key.to_sym, setting]
        end
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

      # `review.adapters`: a list of known coding agents, each named once.
      #
      # @return [Hash{Symbol => Array<String>}] as keywords for {Config.new}
      def review(value, path)
        return {} if value.nil?

        fail_with(path, "review: must be a mapping, e.g. `review: { adapters: [claude, codex] }`") unless value.is_a?(Hash)

        settings = value.transform_keys(&:to_s)
        unknown = settings.keys - REVIEW_KEYS
        fail_with(path, "review: unknown key #{unknown.join(", ")}; known: #{REVIEW_KEYS.join(", ")}") unless unknown.empty?

        { review_adapters: review_adapters(settings["adapters"], path) }
      end

      # @return [Array<String>]
      def review_adapters(value, path)
        names = Array(value).map(&:to_s)
        unknown = names.reject { Adapters.known?(it) }
        fail_with(path, "review.adapters: #{unknown.join(", ")} is not one of #{Adapters.names.join(", ")}") unless unknown.empty?
        fail_with(path, "review.adapters: #{names.tally.select { _2 > 1 }.keys.join(", ")} is named twice") unless names.uniq.size == names.size

        names
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

      # @return [Hash{Symbol => Object}, nil]
      def ci(value, path)
        return nil if value.nil?

        fail_with(path, "ci: must be a mapping, e.g. `ci: { provider: none }`") unless value.is_a?(Hash)

        settings = value.transform_keys(&:to_s)
        unknown = settings.keys - %w[provider config]
        fail_with(path, "ci: unknown key #{unknown.join(", ")}; known: provider, config") unless unknown.empty?

        provider = settings["provider"].to_s.strip.downcase.to_sym
        unless CI_PROVIDERS.include?(provider)
          fail_with(path, "ci.provider: #{settings["provider"].inspect} is not one of #{CI_PROVIDERS.join(", ")}")
        end

        config = settings["config"]
        unless config.nil? || (config.is_a?(String) && !config.strip.empty?)
          fail_with(path, "ci.config: must be a path, not #{config.inspect}")
        end

        { provider:, config: config&.strip }
      end

      # Free text, but never blank: a blank field is one nobody answered,
      # and it is left out rather than written as a placeholder.
      #
      # @return [Hash{Symbol => Object}, nil]
      def stack(value, path)
        return nil if value.nil?

        fail_with(path, "stack: must be a mapping of field to value") unless value.is_a?(Hash)

        fields = value.transform_keys { it.to_s.to_sym }
        unknown = fields.keys - STACK_FIELDS
        unless unknown.empty?
          fail_with(path,
            "stack: unknown field#{"s" unless unknown.size == 1} #{unknown.join(", ")}; " \
            "known: #{STACK_FIELDS.join(", ")}")
        end

        fields.compact.to_h { |field, v| [field, stack_value(field, v, path)] }
      end

      # @return [String, Array<String>]
      def stack_value(field, value, path)
        if STACK_LISTS.include?(field)
          list = Array(value)
          return list.map(&:strip) if list.all? { it.is_a?(String) && !it.strip.empty? }

          fail_with(path, "stack.#{field}: must be a list of names, not #{value.inspect}")
        end
        return value.strip if value.is_a?(String) && !value.strip.empty?

        fail_with(path, "stack.#{field}: must be a non-empty name, not #{value.inspect}")
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

      # `refactor.threshold`: the percent of the codebase, by files or by
      # lines, above which a refactor runs alone (R6). `refactor.lock_hours`:
      # how long its global lock holds before other plans may start again.
      #
      # @return [Hash{Symbol => Numeric}]
      def refactor(value, path)
        return {} if value.nil?

        fail_with(path, "refactor: must be a mapping of setting to value") unless value.is_a?(Hash)

        settings = value.transform_keys(&:to_s)
        (settings.keys - REFACTOR_KEYS).each do |key|
          fail_with(path, "refactor.#{key}: unknown key; known: #{REFACTOR_KEYS.join(", ")}")
        end
        { refactor_threshold:  refactor_threshold(settings["threshold"], path),
          refactor_lock_hours: refactor_lock_hours(settings["lock_hours"], path) }.compact
      end

      # `budget.plan_usd`: a positive dollar figure. Zero is refused rather
      # than read as "no cap", since a plan capped at nothing could never run.
      #
      # @return [Hash{Symbol => Float}] as keywords for {Config.new}
      def budget(value, path)
        return {} if value.nil?

        fail_with(path, "budget: must be a mapping, e.g. `budget: { plan_usd: 5 }`") unless value.is_a?(Hash)

        settings = value.transform_keys(&:to_s)
        (settings.keys - BUDGET_KEYS).each do |key|
          fail_with(path, "budget.#{key}: unknown key; known: #{BUDGET_KEYS.join(", ")}")
        end
        usd = settings["plan_usd"]
        return {} if usd.nil?
        return { budget_plan_usd: usd.to_f } if usd.is_a?(Numeric) && usd.positive?

        fail_with(path, "budget.plan_usd: #{usd.inspect} is not a dollar amount above zero")
      end

      # @return [Integer, nil]
      def refactor_threshold(threshold, path)
        return nil if threshold.nil?
        return threshold if threshold.is_a?(Integer) && threshold.between?(1, 100)

        fail_with(path, "refactor.threshold: #{threshold.inspect} is not a whole percent from 1 to 100")
      end

      # @return [Numeric, nil]
      def refactor_lock_hours(hours, path)
        return nil if hours.nil?
        return hours if hours.is_a?(Numeric) && hours.positive?

        fail_with(path, "refactor.lock_hours: #{hours.inspect} is not a positive number of hours")
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

      # The schema has the last word. The hand checks above give the
      # friendliest message for what they know; anything they let through
      # that the schema refuses is refused here, in the same
      # `<path>: <key>: <problem>` shape. `commands:` is left to
      # {CLI::Base.check_config!}, which knows each command by its aliases.
      #
      # @return [void]
      def schema!(settings, path)
        error = Schema.errors(settings).first
        return if error.nil?

        fail_with(path, "#{schema_key(error)}: #{schema_problem(error)}")
      end

      # @param error [Hash] one json_schemer error
      # @return [String] the dotted key it points at, e.g. `commands.run.bogus`
      def schema_key(error)
        keys = error.fetch("data_pointer").split("/").drop(1).map { it.gsub("~1", "/").gsub("~0", "~") }
        keys.empty? ? "settings" : keys.join(".")
      end

      # @param error [Hash] one json_schemer error
      # @return [Array<String>, nil] the keys a closed mapping knows, when the
      #   error is a key it does not
      def known_keys(error)
        pointer = error.fetch("schema_pointer")
        return nil unless pointer.end_with?("/additionalProperties")

        parent = pointer.delete_suffix("/additionalProperties").split("/").drop(1)
        (parent.empty? ? Schema.document : Schema.document.dig(*parent)).fetch("properties", {}).keys
      end

      # @param error [Hash] one json_schemer error
      # @return [String] what is wrong, with the value as typed
      def schema_problem(error)
        if (known = known_keys(error))
          "unknown key; known: #{known.join(", ")}"
        elsif error.fetch("type") == "enum"
          "#{error.fetch("data").inspect} is not one of #{error.dig("schema", "enum").compact.join(", ")}"
        else
          "#{error.fetch("data").inspect} #{error.fetch("error").sub(/\Avalue at `[^`]*` /, "")}"
        end
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

# frozen_string_literal: true

module OpenLanes
  module Setup
    # The questions `openlanes init` asks, in order: CI, the description
    # (when an API key can read it), who merges, build quality, the stack,
    # port or start fresh, then the four values `init` always asked.
    #
    # One path for both modes. With `ask: false` (`-y`, or no terminal)
    # every answer is a flag, else the current file, else the default; no
    # prompt is touched and no extractor is used, so `-y` makes no network
    # call even with a key set.
    class Interview
      # Said once when no key can read the description.
      NO_KEY = "No ANTHROPIC_API_KEY or OPENAI_API_KEY is set, so every question will be asked."

      CI_QUESTION = "Do you have a CI setup, or would you like some help with that?"

      # Answer → what it records; :help asks which provider next.
      CI_ANSWERS = { "I have one elsewhere" => :external, "Help me set one up" => :help,
                     "No CI for now" => :none }.freeze

      # Provider → the name a person reads, the scaffoldable ones first.
      CI_NAMES = { github_actions: "GitHub Actions", circleci: "CircleCI", jenkins: "Jenkins",
                   gitlab: "GitLab CI", buildkite: "Buildkite" }.freeze

      # Stack field → its question. `from` and `to` come from the port question.
      STACK_QUESTIONS = {
        language:    "Language:",
        frameworks:  "Frameworks (comma-separated):",
        front_end:   "Front end:",
        persistence: "Persistence:",
        caching:     "Caching:",
        logins:      "Logins:",
        deployment:  "Deployment:",
        domain:      "Domain:"
      }.freeze

      QUALITY_QUESTION = "Please indicate the desired quality of the codebase (this affects the severity of items " \
                         "found during review that will require rework):"

      # Label → `desired_codebase_quality` (R4), the default first.
      QUALITY_CHOICES = {
        "High quality, but slower and more expensive: a review-ok-not-perfect PR returns to developers" => :high,
        "Good enough, but faster and cheaper, think MVP: review-ok-not-perfect is accepted"             => :mvp
      }.freeze

      PORT_ANSWERS = ["Port the code", "Start fresh beside it"].freeze

      # The answer offered first when `desired_codebase_quality` is asked
      # and the current file has none. Unasked (`-y`), it stays unset, so the
      # first review that is ok but not perfect asks it instead (R4).
      DEFAULT_QUALITY = :high

      # @param root [String]
      # @param prompt [TTY::Prompt, nil] nil when nothing is asked
      # @param extractor [OpenLanes::Setup::Extractor, nil]
      # @param defaults [OpenLanes::Config] the current file under `--reconfigure`, else empty
      # @param given [Hash{Symbol => Object}] flag values; a question with one is not asked
      # @param ask [Boolean]
      # @param out [IO] where the interview talks
      def initialize(root:, prompt:, extractor:, defaults: Config.new, given: {}, ask: true, out: $stderr)
        @root = root
        @prompt = prompt
        @extractor = extractor
        @defaults = defaults
        @given = given
        @ask = ask
        @out = out
      end

      # @return [OpenLanes::Config] not yet validated; the caller parses it back
      def call
        ci = settle_ci
        extracted = describe
        merge_by = pick(:merge_by, extracted) { choose("Who merges a reviewed pull request?", Config::MERGERS, @defaults.merger) }
        quality = @defaults.desired_codebase_quality || DEFAULT_QUALITY
        desired_codebase_quality = pick(:desired_codebase_quality, extracted) { ask_quality(quality) }
        stack = settle_stack(extracted)

        Config.new(**basics,
          redis_url:                @defaults.redis_url,
          commands:                 @defaults.commands,
          app:                      @defaults.app,
          merge_by:,
          ci:,
          desired_codebase_quality:,
          stack:                    stack.empty? ? nil : stack.to_h)
      end

      private

      def ask? = @ask

      # A flag, else an extracted answer, else the question, else the default.
      def pick(key, extracted, &question)
        return @given[key] if @given.key?(key)
        return extracted[key] if extracted.key?(key)

        ask? ? question.call : default_for(key)
      end

      def default_for(key)
        { merge_by: @defaults.merger, desired_codebase_quality: @defaults.desired_codebase_quality }.fetch(key)
      end

      # @return [Symbol]
      def choose(question, values, default)
        @prompt.select(question, values.map(&:to_s), default: default.to_s).to_sym
      end

      # CI comes first (M21): what the folder runs is named and nothing is
      # asked; with none, the three answers.
      #
      # @return [Hash{Symbol => Object}]
      def settle_ci
        return ci_for(@given[:ci]) if @given.key?(:ci)

        found = Setup.detect_ci(@root)
        return detected_ci(found) unless found.empty?
        return @defaults.ci || ci_for(:none) unless ask?

        answer = CI_ANSWERS.fetch(@prompt.select(CI_QUESTION, CI_ANSWERS.keys))
        return ci_for(answer) unless answer == :help

        names = CiScaffold.providers.to_h { [CI_NAMES.fetch(it), it] }
        ci_for(names.fetch(@prompt.select("Which CI should openlanes set up?", names.keys, default: names.keys.first)))
      end

      # @return [Hash{Symbol => Object}]
      def ci_for(provider) = { provider:, config: CiScaffold::PATHS[provider] }

      # @return [Hash{Symbol => Object}]
      def detected_ci(found)
        @out.puts("CI: found #{found.map { "#{CI_NAMES.fetch(it.provider)} (#{it.path})" }.join(", ")}")
        first = found.first
        { provider: Config::CI_PROVIDERS.include?(first.provider) ? first.provider : :external, config: first.path }
      end

      # @return [Hash{Symbol => Object}] what the description answered
      def describe
        return {} unless ask?

        unless @extractor
          @out.puts(NO_KEY)
          return {}
        end

        description = @prompt.ask("Describe the app you want to build (blank to skip):")
        @extractor.call(description.to_s).tap do |answers|
          @out.puts("From your description: #{answers.keys.join(", ")}") unless answers.empty?
        end
      end

      # @return [OpenLanes::Setup::Stack]
      def settle_stack(extracted)
        detection = Setup.detect_stack(@root)
        base = Stack.from_h(@defaults.stack || detection.stack&.to_h)
        return base unless ask?

        @out.puts("Found more than one language: #{detection.languages.join(", ")}") if detection.mixed?
        fields = STACK_QUESTIONS.to_h do |field, question|
          [field, extracted.key?(field) ? extracted[field] : stack_answer(field, question, base.public_send(field))]
        end
        port(detection, Stack.new(**base.to_h, **fields))
      end

      # @return [String, Array<String>, nil]
      def stack_answer(field, question, current)
        default = Array(current).join(", ")
        answer = @prompt.ask(question, default: default.empty? ? nil : default).to_s.strip
        return nil if answer.empty?

        Config::STACK_LISTS.include?(field) ? answer.split(",").map(&:strip).reject(&:empty?) : answer
      end

      # When the folder already holds a stack and the person is open to
      # another: port the code, or start fresh beside it. A port records both ends.
      #
      # @return [OpenLanes::Setup::Stack]
      def port(detection, stack)
        return stack unless detection.stack
        return stack unless @prompt.yes?("Are you open to a different stack than the one this folder holds?",
          default: false)
        return stack unless @prompt.select("Port the existing code, or start fresh beside it?",
          PORT_ANSWERS) == PORT_ANSWERS.first

        from = [detection.stack.language, *detection.stack.frameworks].join("/")
        to = @prompt.ask("Port to which stack?").to_s.strip
        stack.with(from:, to: to.empty? ? nil : to)
      end

      # The four values `init` has always asked, each from its flag, else
      # asked, else the current file, else its default.
      #
      # @return [Hash{Symbol => Object}]
      def basics
        name = @defaults.project || File.basename(@root)
        project = @given[:project] || (ask? ? @prompt.ask("Project name:", default: name) : name)
        lane = @given[:lane] ||
               (ask? ? @prompt.select("Default lane for new plans:", Plans::Spec::LANES.map(&:to_s)) : @defaults.lane || :full)
        frontend = if @given.key?(:frontend)
                     @given[:frontend]
                   else
                     (ask? ? ask_frontend : @defaults.frontend)
                   end
        jobs = @given[:jobs] || (ask? ? @prompt.ask("Plans to run at once (blank: cores - 2):") : @defaults.jobs)
        { project:, lane: lane.to_sym, frontend:, jobs: count(jobs) }
      end

      # R4's question, worded as `openlanes init` has always asked it.
      #
      # @param default [Symbol]
      # @return [Symbol]
      def ask_quality(default)
        choices = QUALITY_CHOICES.to_h { |label, value| [label, value.to_s] }
        @prompt.select(QUALITY_QUESTION, choices, default: choices.key(default.to_s)).to_sym
      end

      # @return [Boolean, nil]
      def ask_frontend
        choice = @prompt.select("Do plans have a front end?", ["each plan decides", "YES", "NO"])
        { "YES" => true, "NO" => false }[choice]
      end

      # @return [Integer, nil]
      # @raise [OpenLanes::Error] for an answer that is not a count
      def count(value)
        return nil if value.nil? || value.to_s.strip.empty?
        return value.to_s.to_i if value.to_s.match?(/\A[1-9]\d*\z/)

        raise Error, "jobs must be a whole number above zero, not #{value.inspect}"
      end
    end
  end
end

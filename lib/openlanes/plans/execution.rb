# frozen_string_literal: true

module OpenLanes
  module Plans
    # How a plan may run beside the others (R6): `concurrent`, the default,
    # or `global-lock-required`, which the planner agent writes into
    # `plan.md`'s frontmatter for a refactor that touches more of the
    # codebase than {DEFAULT_THRESHOLD} allows. A sweeping rename run beside
    # other work leaves every other branch with conflicts nobody can resolve,
    # so such a plan is built, reviewed and merged alone; {GlobalLock} is the
    # gate that enforces it.
    module Execution
      # The frontmatter key, in `plan.md` first and `spec.md` second.
      KEY = "execution"

      # The modes, the default first.
      CONCURRENT = "concurrent"
      GLOBAL_LOCK = "global-lock-required"
      MODES = [CONCURRENT, GLOBAL_LOCK].freeze

      # What a spec's author writes to say the plan is a refactor.
      REFACTOR_KEY = "implementation_requirement"
      REFACTOR = "refactor"

      # The share of the codebase, in percent by files or by lines, above
      # which a refactor runs alone. `.openlanes.yml` overrides it with
      # `refactor: { threshold: N }`.
      DEFAULT_THRESHOLD = 50

      # The files a mode is read from, in order: the planner writes plan.md,
      # and an author who already knows may say it in the spec.
      SOURCES = %w[plan.md spec.md].freeze

      class << self
        # @param subject [#read] a plan folder
        # @return [String] one of {MODES}; {CONCURRENT} when nothing says
        #   otherwise, or when what it says is not a mode, since a typo must
        #   not stop every other plan in the project
        def of(subject)
          SOURCES.each do |name|
            mode = meta(subject.read(name))[KEY].to_s.strip
            return mode if MODES.include?(mode)
          end
          CONCURRENT
        end

        # @param subject [#read]
        # @return [Boolean] whether the plan must run alone
        def global_lock?(subject) = of(subject) == GLOBAL_LOCK

        # @param subject [#read]
        # @return [Boolean] whether spec.md's frontmatter calls it a refactor,
        #   by `implementation_requirement: refactor` or a `refactor` entry
        #   in the `implementation_requirements` list
        def refactor?(subject)
          spec = meta(subject.read(Spec::FILENAME))
          said = [spec[REFACTOR_KEY], *Array(spec[Spec::REQUIREMENTS_KEY])]
          said.any? { it.to_s.strip == REFACTOR }
        end

        # The mode a refactor's estimate earns: over the threshold by files
        # or by lines, either one, means it runs alone. Each measure is a
        # `[touched, total]` pair, so the part can never be passed without
        # the whole it is a share of.
        #
        # @param files [Array(Integer, Integer)] files touched, files tracked
        # @param lines [Array(Integer, Integer)] lines touched, lines tracked
        # @param threshold [Integer] percent
        # @return [String] one of {MODES}
        def classify(files:, lines: [0, 0], threshold: DEFAULT_THRESHOLD)
          over = [files, lines].any? { |(part, whole)| share(part, whole) > threshold }
          over ? GLOBAL_LOCK : CONCURRENT
        end

        # @param part [Integer]
        # @param whole [Integer]
        # @return [Float] percent, 0 when there is no whole to share
        def share(part, whole) = whole.to_i.positive? ? part.to_f * 100 / whole : 0.0

        private

        # @param text [String, nil]
        # @return [Hash] the frontmatter, empty when absent or unreadable
        def meta(text)
          text.nil? ? {} : Frontmatter.split(text).first.transform_keys(&:to_s)
        rescue Psych::Exception
          {}
        end
      end
    end
  end
end

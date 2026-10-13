# frozen_string_literal: true

module OpenLanes
  module Plans
    # What the author of `spec.md` asked of the harness, in its frontmatter:
    #
    #   ---
    #   lane: quick              # full (default) | plan | quick
    #   frontend: false          # true forces rey-frontend, false forbids it
    #   depth: fast              # fast | medium | deep
    #   phases:
    #     build:  { adapter: codex, model: gpt-5-codex, effort: medium }
    #     review: { model: opus }
    #   implementation_suggestions:
    #     - Ruby, with dry-cli for the command line
    #     - Reuse the gems already in the Gemfile before adding new ones
    #   implementation_requirements:
    #     - The database is PG-strict
    #   task-completed-when:
    #     - `openlanes create` opens an editor and writes no draft
    #   how-to-verify:
    #     - bundle exec rspec spec/openlanes/cli/create_spec.rb
    #   ---
    #
    # The body is the specification; this is how it should be worked. A value
    # this does not recognise is ignored and named in {#problems}, rather than
    # stopping the run: a typo in `lane:` should cost the author their lane,
    # not their plan.
    #
    # @!attribute [r] lane
    #   @return [Symbol] :full, :plan or :quick
    # @!attribute [r] frontend
    #   @return [Boolean, nil] nil when the plan decides
    # @!attribute [r] depth
    #   @return [Symbol, nil] :fast, :medium or :deep
    # @!attribute [r] phases
    #   @return [Hash{String => Hash{String => String}}] per-phase
    #     `adapter`, `model` and `effort`
    # @!attribute [r] suggestions
    #   @return [Array<String>] the author's `implementation_suggestions`:
    #     language, libraries, an approach. Offered to the agents, never
    #     imposed on them.
    # @!attribute [r] requirements
    #   @return [Array<String>] the author's `implementation_requirements`:
    #     constraints the work must meet exactly as written.
    # @!attribute [r] completed_when
    #   @return [Array<String>] the author's `task-completed-when`: what
    #     must be true for the task to count as finished.
    # @!attribute [r] how_to_verify
    #   @return [Array<String>] the author's `how-to-verify`: the commands or
    #     checks that show it is.
    # @!attribute [r] problems
    #   @return [Array<String>] what was ignored, and why
    Spec = Data.define(:lane,
      :frontend,
      :depth,
      :phases,
      :suggestions,
      :requirements,
      :completed_when,
      :how_to_verify,
      :problems) do
      def initialize(lane: :full, frontend: nil, depth: nil, phases: {}, suggestions: [], requirements: [],
        completed_when: [], how_to_verify: [], problems: [])
        super
      end

      # @param phase [String, Symbol, nil]
      # @return [Hash{String => String}] what the author set for that phase
      def override_for(phase) = phases.fetch(phase.to_s, {})

      # @return [Boolean]
      def default? = self == Spec.new
    end

    class Spec
      # Every route a plan can take through the agents.
      #   full  — research, specification, planning, build, review
      #   plan  — the spec is already what the author wants: plan, build, review
      #   quick — a short mechanical task: one agent builds it, then review
      LANES = %i[full plan quick].freeze

      # How much each phase should think, and what an eval holds it to.
      DEPTHS = %i[fast medium deep].freeze

      # What a depth means as an effort, when nothing more specific is set.
      EFFORT_FOR_DEPTH = { fast: "low", medium: "medium", deep: "high" }.freeze

      # The keys a `phases:` entry may set.
      PHASE_KEYS = %w[adapter model effort].freeze

      # The frontmatter key for what the author would build it with. Optional,
      # and a suggestion: an agent that finds a better route takes it and says
      # why, so nothing here is validated against what is installed.
      SUGGESTIONS_KEY = "implementation_suggestions"

      # The other side of {SUGGESTIONS_KEY}: constraints the agents must meet
      # exactly as written (`The database is PG-strict`). They are not weighed
      # against anything, so an agent that cannot meet one signs Blocked
      # instead of substituting its own.
      REQUIREMENTS_KEY = "implementation_requirements"

      # How the author says the task is finished, and how to tell. Hyphenated
      # because that is how the author named them; they are copied into
      # `plan.md` by {OpenLanes::Lifecycle::Completion}.
      COMPLETED_WHEN_KEY = "task-completed-when"
      HOW_TO_VERIFY_KEY = "how-to-verify"

      FILENAME = "spec.md"

      class << self
        # @param subject [#read]
        # @return [OpenLanes::Plans::Spec]
        def for(subject) = parse(subject.read(FILENAME).to_s)

        # @param dir [String] a plan folder
        # @return [OpenLanes::Plans::Spec]
        def load(dir)
          path = File.join(dir, FILENAME)
          File.file?(path) ? parse(File.read(path, encoding: "UTF-8")) : new
        end

        # @param text [String] a whole spec.md
        # @return [OpenLanes::Plans::Spec]
        def parse(text)
          meta, = Frontmatter.split(text)
          from(meta)
        rescue Psych::Exception => e
          new(problems: ["spec.md frontmatter is not valid YAML (#{e.message.lines.first.strip})"])
        end

        # @param meta [Hash]
        # @return [OpenLanes::Plans::Spec]
        def from(meta)
          problems = []
          new(lane:     choice(meta, "lane", LANES, :full, problems),
            frontend: switch(meta, "frontend", problems),
            depth:    choice(meta, "depth", DEPTHS, nil, problems),
            phases:   phases(meta["phases"], problems),
            suggestions: notes(meta, SUGGESTIONS_KEY, problems),
            requirements: notes(meta, REQUIREMENTS_KEY, problems),
            completed_when: notes(meta, COMPLETED_WHEN_KEY, problems),
            how_to_verify: notes(meta, HOW_TO_VERIFY_KEY, problems),
            problems:)
        end

        private

        # @return [Symbol, nil]
        def choice(meta, key, allowed, default, problems)
          return default unless meta.key?(key)

          value = meta[key].to_s.strip.downcase.to_sym
          return value if allowed.include?(value)

          problems << "#{key}: #{meta[key].inspect} is not one of #{allowed.join(", ")}"
          default
        end

        # @return [Boolean, nil]
        def switch(meta, key, problems)
          return nil unless meta.key?(key)
          return meta[key] if [true, false].include?(meta[key])

          problems << "#{key}: #{meta[key].inspect} is not true or false"
          nil
        end

        # A bare string is one item; a list is several.
        #
        # @param key [String] one of the keys above that holds free text
        # @return [Array<String>]
        def notes(meta, key, problems)
          return [] if meta[key].nil?

          items = meta[key].is_a?(Array) ? meta[key] : [meta[key]]
          unless items.all? { |item| item.is_a?(String) || item.is_a?(Numeric) }
            problems << "#{key}: must be text or a list of text"
            return []
          end

          items.map { |item| item.to_s.strip }.reject(&:empty?)
        end

        # @return [Hash]
        def phases(value, problems)
          return {} if value.nil?

          unless value.is_a?(Hash)
            problems << "phases: must be a mapping of phase to adapter, model and effort"
            return {}
          end

          value.each_with_object({}) do |(phase, settings), out|
            next problems << "phases.#{phase}: must be a mapping" unless settings.is_a?(Hash)

            kept = settings.transform_keys(&:to_s).slice(*PHASE_KEYS).transform_values(&:to_s)
            (settings.keys.map(&:to_s) - PHASE_KEYS).each { |k| problems << "phases.#{phase}.#{k}: unknown key" }
            if kept.key?("effort") && !Adapters.effort?(kept["effort"])
              problems << "phases.#{phase}.effort: #{kept["effort"].inspect} is not one of #{Adapters::EFFORTS.join(", ")}"
              kept.delete("effort")
            end
            if kept.key?("adapter") && !Adapters.known?(kept["adapter"])
              problems << "phases.#{phase}.adapter: #{kept["adapter"].inspect} is not one of #{Adapters.names.join(", ")}"
              kept.delete("adapter")
            end
            out[phase.to_s] = kept
          end
        end
      end
    end
  end
end

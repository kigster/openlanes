# frozen_string_literal: true

module OpenLanes
  module Plans
    # What the author of `spec.md` asked of the harness, in its frontmatter:
    #
    #   ---
    #   starts: building         # research (default) | planning | building
    #   frontend: false          # true forces frontend-coder, false forbids it
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
    #   depends_on: ["034.00"]   # plans that must be ✅ before this one starts
    #   ---
    #
    # The body is the specification; this is how it should be worked. A value
    # this does not recognise is ignored and named in {#problems}, rather than
    # stopping the run: a typo in `starts:` should cost the author where the
    # plan starts, not the plan.
    #
    # @!attribute [r] starts
    #   @return [Symbol] :research, :planning or :building
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
    # @!attribute [r] depends_on
    #   @return [Array<String>, nil] canonical `NNN.MM` ordinals of the plans
    #     this one waits for, `[]` for `[none]`. nil when the key is absent.
    #     Whether the key is answered is {#linked}, not this list: `[]` and
    #     `[none]` both read as no edges.
    # @!attribute [r] linked
    #   @return [Boolean] whether an agent or a person has answered the key:
    #     `[none]`, or quoted plan numbers and nothing else. A missing key and
    #     a bare `[]` are unanswered, since `[]` is what a template leaves
    #     behind as often as what a planner writes on purpose. So is a value
    #     with anything else in it (`[soon]`, `""`, the octal `[034]`): it
    #     names no plan, and the planner rewrites it.
    # @!attribute [r] how_to_test
    #   @return [Array<String>] the items under {HOW_TO_TELL} in the body, or
    #     {#how_to_verify} when the spec has no such section (until plan 007).
    # @!attribute [r] problems
    #   @return [Array<String>] what was ignored, and why
    Spec = Data.define(:starts,
      :frontend,
      :depth,
      :phases,
      :suggestions,
      :requirements,
      :completed_when,
      :how_to_verify,
      :depends_on,
      :linked,
      :how_to_test,
      :problems) do
      def initialize(starts: :research, frontend: nil, depth: nil, phases: {}, suggestions: [], requirements: [],
        completed_when: [], how_to_verify: [], how_to_test: [], depends_on: nil, linked: false, problems: [])
        super
      end

      # @return [Boolean] see {#linked}
      def linked? = linked

      # @param phase [String, Symbol, nil]
      # @return [Hash{String => String}] what the author set for that phase
      def override_for(phase) = phases.fetch(phase.to_s, {})

      # @return [Boolean]
      def default? = self == Spec.new
    end

    class Spec
      # Where a plan starts. {Lifecycle::Lanes} jumps `planning` and `building`
      # past the phases before that point; `research` walks the spine.
      #   research — research, specification, planning, build, review
      #   planning — the spec is already what the author wants: plan, build, review
      #   building — a short mechanical task: one agent builds it, then review
      STARTS = %i[research planning building].freeze

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

      # The plans this one waits for. Quoted canonical ordinals only: YAML
      # reads a bare `[034]` as octal 28, a silent wrong answer.
      DEPENDS_ON_KEY = "depends_on"

      # The one word {DEPENDS_ON_KEY} takes besides a plan number:
      # `depends_on: [none]` says someone looked and found nothing, where
      # `[]` cannot be told apart from a template nobody filled in.
      NO_DEPENDENCIES = "none"

      # Where `how-to-verify:` lives now (decision M10): a section of the
      # spec's body, written by its author like every other, rather than a
      # key in its frontmatter. `resync dirs` moves the key's items here.
      HOW_TO_VERIFY_HEADING = "## How to tell it's working?"

      # The same section, by the name the publisher refuses a pull request
      # without: plan.md must carry its copy.
      HOW_TO_TELL = HOW_TO_VERIFY_HEADING

      # The heading on a line of its own. An author's editor may type a curly apostrophe (`it’s`) or leave the
      # question mark off; either must still find the section, not drop the
      # checks without a word.
      HOW_TO_VERIFY_LINE = /^##[ \t]+how to tell it['‘’]s working\??[ \t]*$/i

      FILENAME = "spec.md"

      # A list item under the heading; +marker+ ends at its content column.
      LIST_ITEM = /\A(?<marker>\s*(?:[-*]|\d+\.)\s+)(?<text>.+)/

      # The opening of a fenced code block, and its fence.
      FENCE = /\A(\s*)(`{3,}|~{3,})/

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

        # The spec's first paragraph of prose, which the dashboard shows when a
        # person hovers a plan's title: headings, comments, lists, quotes and
        # code are passed over, so a spec that opens with `## Problem
        # statement` answers with the problem itself.
        #
        # @param text [String] a whole spec.md
        # @param limit [Integer] characters kept, the rest cut at a word
        # @return [String] "" when the spec has no prose paragraph
        def summary(text, limit: 600)
          _, body = Frontmatter.split(text)
          paragraph = body.to_s.gsub(/<!--.*?-->/m, "").split(/\n\s*\n/).map(&:strip).find do |block|
            !block.empty? && !block.match?(/\A(?:#|>|[-*+] |\d+\. |```|~~~|\||<)/)
          end.to_s.gsub(/\s*\n\s*/, " ")
          paragraph.length > limit ? "#{paragraph[0, limit].sub(/\s+\S*\z/, "")}…" : paragraph
        rescue Psych::Exception
          ""
        end

        # @param text [String] a whole spec.md
        # @return [OpenLanes::Plans::Spec]
        def parse(text)
          meta, body = Frontmatter.split(text)
          spec = from(meta)
          told = section_items(body.to_s)
          checks = (spec.how_to_verify + told).uniq
          # how_to_test prefers the body's own section; the frontmatter key
          # stands in until plan 007 migrates old specs.
          spec.with(how_to_verify: checks, how_to_test: told.empty? ? spec.how_to_verify : told)
        rescue Psych::Exception => e
          new(problems: ["spec.md frontmatter is not valid YAML (#{e.message.lines.first.strip})"])
        end

        # Move a `how-to-verify:` frontmatter key into the body (M10): its
        # items are appended to `## How to tell it's working?`, which is added
        # at the end when the spec has none. The rest of the frontmatter is
        # kept as written, comments and all, and a frontmatter left empty is
        # dropped.
        #
        # @param text [String] a whole spec.md
        # @return [String] +text+ itself when there is no key to move, or no
        #   way to remove it that leaves the other keys exactly as they were
        def migrate_how_to_verify(text)
          match = Frontmatter::PATTERN.match(text) or return text
          meta, = Frontmatter.split(text)
          return text unless meta.key?(HOW_TO_VERIFY_KEY)

          front = without_key("#{match[1]}\n", HOW_TO_VERIFY_KEY, meta) or return text
          items = notes(meta, HOW_TO_VERIFY_KEY, [])
          head = front.strip.empty? ? "" : "---\n#{front}---\n"
          "#{head}#{append_checks(match[2], items)}"
        rescue Psych::Exception
          text
        end

        # One check as a Markdown list item. A check written as a YAML block
        # scalar spans lines; its continuation lines are indented under the
        # item, so they stay part of it rather than becoming loose prose.
        #
        # @param item [String]
        # @return [String] without a trailing newline
        def list_item(item) = "- #{item.gsub("\n", "\n  ")}"

        # @param meta [Hash]
        # @return [OpenLanes::Plans::Spec]
        def from(meta)
          problems = []
          new(starts:     choice(meta, "starts", STARTS, :research, problems),
            frontend: switch(meta, "frontend", problems),
            depth:    choice(meta, "depth", DEPTHS, nil, problems),
            phases:   phases(meta["phases"], problems),
            suggestions: notes(meta, SUGGESTIONS_KEY, problems),
            requirements: notes(meta, REQUIREMENTS_KEY, problems),
            completed_when: notes(meta, COMPLETED_WHEN_KEY, problems),
            how_to_verify: notes(meta, HOW_TO_VERIFY_KEY, problems),
            depends_on: depends_on(meta, problems),
            linked: linked?(meta),
            how_to_test: notes(meta, HOW_TO_VERIFY_KEY, []),
            problems:)
        end

        private

        # The YAML source of +yaml+ with +key+'s entry cut out, from the
        # key's line to the end of its value as Psych located them. A regex
        # over the text took a blank line between list items for the end of
        # the entry, leaving the later items behind, and never matched a
        # quoted key at all. The cut is kept only when what is left loads as
        # the same mapping less that key; anything else (a flow mapping, a key
        # sharing a line) is not cut.
        #
        # @param yaml [String]
        # @param key [String]
        # @param meta [Hash] +yaml+, loaded
        # @return [String, nil]
        def without_key(yaml, key, meta)
          root = Psych.parse(yaml)&.root
          return nil unless root.is_a?(Psych::Nodes::Mapping)

          name, value = root.children.each_slice(2).find { |k, _| k.is_a?(Psych::Nodes::Scalar) && k.value == key }
          return nil unless name

          stop = value.end_column.zero? ? value.end_line : value.end_line + 1
          lines = yaml.lines
          rest = (lines[0...name.start_line] + lines[stop..].to_a).join
          left, = Frontmatter.split("---\n#{rest}\n---\n")
          rest if left == meta.except(key)
        end

        # The checks under `## How to tell it's working?`, in document order,
        # up to the next heading of the same level. The owner wants how-to-test
        # as specific and technical as it can be, and prose can be just as
        # specific as a bullet (2026-10-14, on M10), so prose is a check too
        # rather than the author's aside that the agents never see:
        #
        # - A list item is one check, with its indented continuation lines and
        #   any fenced block indented under it, blank lines in the fence
        #   included. Its lines lose the item's indent and keep the rest, so
        #   a command's own indentation survives.
        # - A prose paragraph (consecutive non-blank, non-list lines) is one
        #   check, its lines as written.
        # - A fenced block not indented under an item joins the prose
        #   paragraph just before it, or is a check of its own.
        #
        # Inside a fence nothing is a list item or a heading, so a
        # `- not an item` line there stays in the code. {list_item} writes any
        # of these back as one item, which this reads back unchanged.
        #
        # @param body [String]
        # @return [Array<String>]
        def section_items(body)
          start = body =~ HOW_TO_VERIFY_LINE or return []
          checks = []
          state = { kind: nil, indent: 0, fence: nil }
          body[start..].lines.drop(1).each do |line|
            line = line.chomp
            if state[:fence]
              fence_line(checks, state, line)
            elsif line.start_with?("## ")
              break
            else
              section_line(checks, state, line)
            end
          end
          checks.map(&:strip)
        end

        # A line inside a fenced block, the closing fence included.
        def fence_line(checks, state, line)
          checks[-1] = "#{checks.last}\n#{state[:kind] == :item ? dedent(line, state[:indent]) : line}"
          fence = state[:fence]
          state[:fence] = nil if line.strip.match?(/\A#{Regexp.escape(fence[0])}{#{fence.length},}\z/)
        end

        # A line outside any fence: it opens a fence, an item or a paragraph,
        # or continues the one it follows.
        def section_line(checks, state, line)
          if (fence = line[FENCE, 2])
            open_fence(checks, state, line, fence)
          elsif (item = line.match(LIST_ITEM))
            checks << item[:text]
            state.merge!(kind: :item, indent: item.end(:marker))
          elsif line.strip.empty?
            state[:kind] = :after_prose if state[:kind] == :prose
          elsif state[:kind] == :item && line.match?(/\A[ \t]/)
            checks[-1] = "#{checks.last}\n#{dedent(line, state[:indent])}"
          elsif state[:kind] == :prose
            checks[-1] = "#{checks.last}\n#{line}"
          else
            checks << line
            state[:kind] = :prose
          end
        end

        # An indented fence under an open item belongs to it; any other joins
        # the paragraph before it, or starts a check of its own.
        def open_fence(checks, state, line, fence)
          if state[:kind] == :item && line.match?(/\A[ \t]/)
            checks[-1] = "#{checks.last}\n#{dedent(line, state[:indent])}"
          elsif %i[prose after_prose].include?(state[:kind])
            checks[-1] = "#{checks.last}\n#{line}"
            state[:kind] = :prose
          else
            checks << line
            state[:kind] = :prose
          end
          state[:fence] = fence
        end

        # +line+ less up to +indent+ leading blanks.
        def dedent(line, indent) = line.sub(/\A[ \t]{0,#{indent}}/, "")

        # @param body [String]
        # @param items [Array<String>]
        # @return [String]
        def append_checks(body, items)
          list = items.map { "#{list_item(it)}\n" }.join
          body = "#{body}\n" unless body.end_with?("\n")
          start = body =~ HOW_TO_VERIFY_LINE
          return "#{body.rstrip}\n\n#{HOW_TO_VERIFY_HEADING}\n\n#{list}" unless start

          heading_end = start + body[start..].index("\n").to_i + 1
          rest = body[heading_end..].to_s
          stop = rest =~ /^## / || rest.length
          section = rest[0...stop].rstrip
          joined = section.empty? ? "\n#{list}" : "#{section}\n#{list}"
          tail = stop < rest.length ? "\n#{rest[stop..]}" : ""
          "#{body[0...heading_end]}#{joined}#{tail}"
        end

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

        # Each entry must be a string {Ordinal} can read; anything else is
        # dropped and named, never coerced, since `034` has already become 28
        # by the time it reaches here. `"034"` is normalised to `"034.00"`, so
        # every caller compares one form.
        #
        # {NO_DEPENDENCIES} on its own reads as `[]`: no edges, and no
        # problem. Beside a plan number it contradicts that number, so it is
        # named and dropped, and the numbers stand.
        #
        # @return [Array<String>, nil] nil when the key is absent
        def depends_on(meta, problems)
          return nil unless meta.key?(DEPENDS_ON_KEY)

          items = dependency_items(meta)
          if items.include?(NO_DEPENDENCIES)
            items -= [NO_DEPENDENCIES]
            problems << "#{DEPENDS_ON_KEY}: #{NO_DEPENDENCIES} cannot stand beside a plan number" if items.any?
          end
          items.filter_map do |item|
            ordinal = item.is_a?(String) && Ordinal.parse(item)
            next ordinal.to_s if ordinal

            problems << "#{DEPENDS_ON_KEY}: #{item.inspect} is not a quoted plan number like \"034.00\""
            nil
          end.uniq.sort
        end

        # @return [Array<Object>] the key's entries, a scalar as one entry
        def dependency_items(meta)
          value = meta[DEPENDS_ON_KEY]
          value.nil? ? [] : Array(value)
        end

        # @return [Boolean] true for `[none]` or a list of quoted plan numbers
        def linked?(meta)
          items = dependency_items(meta)
          items.any? && items.all? { it == NO_DEPENDENCIES || (it.is_a?(String) && Ordinal.parse(it)) }
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

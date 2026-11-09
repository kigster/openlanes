# frozen_string_literal: true

module OpenLanes
  module Memory
    # One lesson: a markdown file whose frontmatter says who it is for and
    # whose body says what to do.
    #
    #   ---
    #   id: L-0042
    #   title: Specs build real .plans trees, never mock the filesystem
    #   applies_to: [backend-coder, build]
    #   checked_by: [staff-reviewer]
    #   severity: high
    #   status: active
    #   ---
    #
    # `applies_to` and `checked_by` take agent names or phases, so one fact
    # learnt by a reviewer reaches every builder that needs it without being
    # copied into each agent's file.
    #
    # Everything here reaches a prompt, so nothing here is trusted. A lesson
    # stays a candidate until it says `status: active`, and the id, the title
    # and every name must each be one plain line: a title with a newline in it
    # could otherwise open a `## Boundary` section of its own (PR 196).
    #
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] title
    #   @return [String] the one line an agent sees in its prompt
    # @!attribute [r] applies_to
    #   @return [Array<String>] agent names or phases that should follow it
    # @!attribute [r] checked_by
    #   @return [Array<String>] agent names or phases that should cite it when it is broken
    # @!attribute [r] kind
    #   @return [Symbol] one of {KINDS}
    # @!attribute [r] severity
    #   @return [Symbol] one of {SEVERITIES}
    # @!attribute [r] status
    #   @return [Symbol] one of {STATUSES}; only `:active` reaches a prompt
    # @!attribute [r] confirmed
    #   @return [Date, nil] when evidence or a person last confirmed it
    # @!attribute [r] path
    #   @return [String] where it came from, for problem reports
    # @!attribute [r] cite
    #   @return [String] what the prompt tells an agent to read for the full text
    # @!attribute [r] scope
    #   @return [Symbol] `:project` or `:global`
    Lesson = Data.define(:id, :title, :applies_to, :checked_by, :kind, :severity, :status, :confirmed, :path, :cite, :scope) do
      # The ranking order: a lesson whose violation costs a review round
      # comes before one that costs a comment.
      const_set(:SEVERITIES, %i[high medium low].freeze)

      const_set(:KINDS, %i[practice pitfall decision struck].freeze)

      # `candidate` waits for promotion; `graduated` became a rule, a check
      # or a skill and is enforced elsewhere; `retired` stopped being true.
      const_set(:STATUSES, %i[active candidate graduated retired].freeze)

      # Matches every agent, for a project-wide rule.
      const_set(:EVERYONE, "all")

      # A file that cannot be read as a lesson. Kept apart from a crash so one
      # bad file costs one lesson, not every agent's prompt.
      const_set(:Invalid, Class.new(StandardError))

      # What a choice a person leaves out reads as. A lesson that does not
      # say it is active is not: a file someone dropped in the directory,
      # rather than promoted, never reaches a prompt.
      const_set(:DEFAULTS, { "kind" => :practice, "severity" => :medium, "status" => :candidate }.freeze)

      # An id is cited in findings and printed in prompts, so it is a token,
      # not prose.
      const_set(:ID, /\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/)

      # An agent name or a phase, as `agents/*.md` spells them.
      const_set(:NAME, /\A[a-z0-9][a-z0-9_-]{0,63}\z/i)

      # The longest title that still reads as one line of a list.
      const_set(:TITLE_MAX, 200)

      # Control characters, and the Unicode line and paragraph separators a
      # model may also read as a line break.
      const_set(:BREAKS, /[[:cntrl:]\u0085\u2028\u2029]/)

      class << self
        # @param entry [OpenLanes::Memory::Entry]
        # @param scope [Symbol]
        # @return [OpenLanes::Memory::Lesson]
        # @raise [OpenLanes::Memory::Lesson::Invalid]
        def parse(entry, scope:)
          path = entry.path
          meta, = Frontmatter.split(utf8(entry.text, path))
          new(**audience(meta, path), **choices(meta, path), path:, cite: entry.cite, scope:)
        rescue Psych::Exception => e
          raise self::Invalid, "#{path}: frontmatter is not valid YAML (#{e.message.lines.first.strip})"
        end

        private

        # @return [String]
        def utf8(text, path)
          text = text.dup.force_encoding(Encoding::UTF_8)
          raise self::Invalid, "#{path}: not valid UTF-8" unless text.valid_encoding?

          text
        end

        def audience(meta, path)
          { id:         token(meta, "id", path, self::ID),
            title:      title(meta, path),
            applies_to: names(meta, "applies_to", path, required: true),
            checked_by: names(meta, "checked_by", path) }
        end

        def choices(meta, path)
          { kind:      choice(meta, "kind", self::KINDS, path),
            severity:  choice(meta, "severity", self::SEVERITIES, path),
            status:    choice(meta, "status", self::STATUSES, path),
            confirmed: date(meta, path) }
        end

        def required(meta, key, path)
          value = meta[key].to_s.strip
          raise self::Invalid, "#{path}: `#{key}:` is missing" if value.empty?

          value
        end

        def token(meta, key, path, pattern)
          value = required(meta, key, path)
          return value if value.match?(pattern)

          raise self::Invalid, "#{path}: `#{key}:` must be one word of letters, digits, `.`, `_` or `-`"
        end

        def title(meta, path)
          value = required(meta, "title", path)
          raise self::Invalid, "#{path}: `title:` must be one line" if value.match?(self::BREAKS)
          raise self::Invalid, "#{path}: `title:` is longer than #{self::TITLE_MAX} characters" if value.size > self::TITLE_MAX

          value
        end

        def names(meta, key, path, required: false)
          list = Array(meta[key]).map { it.to_s.strip }.reject(&:empty?)
          raise self::Invalid, "#{path}: `#{key}:` names no agent or phase" if required && list.empty?

          bad = list.grep_v(self::NAME)
          raise self::Invalid, "#{path}: `#{key}:` holds #{bad.first.inspect}, not an agent or a phase" if bad.any?

          list
        end

        def choice(meta, key, allowed, path)
          return self::DEFAULTS.fetch(key) if meta[key].nil?

          value = meta[key].to_s.strip.to_sym
          return value if allowed.include?(value)

          raise self::Invalid, "#{path}: `#{key}: #{meta[key]}` is not one of #{allowed.join(", ")}"
        end

        def date(meta, path)
          value = meta["confirmed"]
          return value if value.nil? || value.is_a?(Date)

          Date.iso8601(value.to_s)
        rescue Date::Error
          raise self::Invalid, "#{path}: `confirmed: #{value}` is not a date (YYYY-MM-DD)"
        end
      end

      # @return [Boolean] whether it reaches a prompt at all
      def active? = status == :active

      # @param agent [OpenLanes::Agents::Agent]
      # @return [Boolean] whether +agent+ should follow it
      def for?(agent) = names?(applies_to, agent)

      # @param agent [OpenLanes::Agents::Agent]
      # @return [Boolean] whether +agent+ should cite it when a diff breaks it
      def checked_by?(agent) = names?(checked_by, agent)

      private

      def names?(list, agent) = list.include?(self.class::EVERYONE) || list.include?(agent.name) || list.include?(agent.phase.to_s)
    end
  end
end

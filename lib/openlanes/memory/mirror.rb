# frozen_string_literal: true

module OpenLanes
  module Memory
    # Decision C3: what one project has learnt reaches every project on the
    # machine, once a second project has learnt it too.
    #
    # It mirrors a project's *active* lessons, read from the default branch,
    # never its inbox and never a memory pull request still open: a lesson
    # is promoted only when a person merges it, and mirroring at the time
    # the pull request opened would carry a lesson that person may yet
    # reject into every other project's prompt. Reading the merged lessons
    # also makes it idempotent, so the engine runs it at the end of every
    # run and a lesson merged between runs is picked up by the next one.
    #
    # - A lesson no global record matches becomes a candidate in the global
    #   inbox, tagged with the project (`projects:`).
    # - One a candidate matches tags it with this project too; once two
    #   distinct projects hold it, it turns active as `G-NNNN-<slug>.md`.
    #   No review: the store is the operator's own and is never committed.
    # - One an active global lesson matches adds this project to it.
    #
    # Lesson ids are per project (two projects each have an `L-0001` that
    # say different things), so "the same lesson" is the same slug, or the
    # same title once case and punctuation are dropped. A global lesson gets
    # a `G-` id of its own so it cannot take a project's `L-` id; on the
    # merged read path a project lesson with the same id still wins.
    #
    # Every read and write goes through {GlobalStore}, under its lock, since
    # two runs in two projects may finish at once.
    class Mirror
      # One project lesson, and what the sync did with it.
      #
      # @!attribute [r] kind
      #   @return [Symbol] `:candidate` (new in the global inbox), `:tagged`
      #     (a candidate gained this project), `:activate` (it turned
      #     active), `:joined` (an active one gained this project), `:known`
      #     (nothing to do) or `:refuse` (the secret scan or the lesson
      #     checks refused the file)
      # @!attribute [r] slug
      #   @return [String]
      # @!attribute [r] id
      #   @return [String, nil] the global id, once it has one
      # @!attribute [r] why
      #   @return [String, nil] why it was refused
      Change = Data.define(:kind, :slug, :id, :why) do
        def initialize(id: nil, why: nil, **) = super
      end

      # Distinct projects a lesson must be held by before it turns active.
      THRESHOLD = 2

      # One active project lesson: its file as the inbox reads one, and the
      # id it has in its project.
      Sighting = Data.define(:record, :id) do
        # @return [String]
        def slug = record.slug
      end
      private_constant :Sighting

      # @param project [String] {ProjectKey} of the project mirrored
      # @param source [#entries] the project's merged lessons, a {Committed}
      # @param store [OpenLanes::Memory::GlobalStore]
      # @param today [#call] returns the current `Date`
      def initialize(project:, source:, store:, today: -> { Date.today })
        @project = project
        @source = source
        @store = store
        @today = today
      end

      # @return [Array<OpenLanes::Memory::Mirror::Change>] one per active project lesson
      def call
        sightings = active_lessons
        return [] if sightings.empty?

        @store.locked { sightings.map { mirror(it) } }
      end

      private

      # @return [Array<Sighting>]
      def active_lessons
        @source.entries.grep(Entry).filter_map do |entry|
          lesson = Lesson.parse(entry, scope: :project)
          next unless lesson.active?

          meta, body = Frontmatter.split(entry.text.dup.force_encoding(Encoding::UTF_8))
          record = Candidate.new(slug: slug_of(entry, lesson), meta:, body: body.to_s.strip, path: entry.path)
          Sighting.new(record:, id: lesson.id)
        rescue Lesson::Invalid, Psych::Exception
          nil
        end
      end

      # The file name without its id: `L-0007-real-trees.md` is
      # `real-trees`, the slug {Promotion} wrote it from. {Committed} cites a
      # path as `<path> at <sha>`, so that suffix goes first. A file named
      # only by its id (`L-1.md`) has no slug, and two projects' `L-1` are
      # unrelated, so the title stands in for one.
      #
      # @return [String]
      def slug_of(entry, lesson)
        name = File.basename(entry.path.sub(/ at \h{7,}\z/, ""), ".md")
        slug = name.delete_prefix("#{lesson.id}-").sub(/\AL-\d{4,}-/, "").downcase
        return slug unless slug == lesson.id.downcase

        title_key(lesson.title).tr(" ", "-")[0, 64].delete_suffix("-")
      end

      # @param sighting [Sighting]
      # @return [OpenLanes::Memory::Mirror::Change]
      def mirror(sighting)
        active = find(@store.mirrored, sighting)
        return join(active, sighting) if active

        waiting = find(@store.candidates, sighting)
        return file(sighting) unless waiting
        return Change.new(kind: :known, slug: waiting.slug) if tagged?(waiting)

        tag(waiting, sighting)
      end

      # @return [OpenLanes::Memory::Mirror::Change]
      def join(active, sighting)
        # A candidate left beside its active lesson by a sync that died
        # between writing one and removing the other.
        @store.remove(find(@store.candidates, sighting))
        change = Change.new(kind: :joined, slug: active.slug, id: active.meta["id"].to_s)
        return change.with(kind: :known) if tagged?(active)

        settled(change, @store.write(active.path, merged(active.meta, sighting).merge("confirmed" => @today.call), active.body))
      end

      # @return [OpenLanes::Memory::Mirror::Change]
      def file(sighting)
        slug = sighting.slug
        return Change.new(kind: :refuse, slug:, why: "slug is not a lesson id") unless slug.match?(Lesson::ID)

        meta = sighting.record.meta.slice("title", "applies_to", "checked_by", "kind", "severity")
                       .merge("id" => slug, "slug" => slug, "status" => "candidate", "proposed" => @today.call)
        settled(Change.new(kind: :candidate, slug:), @store.write(@store.candidate_path(slug), merged(meta, sighting), sighting.record.body))
      end

      # @return [OpenLanes::Memory::Mirror::Change]
      def tag(waiting, sighting)
        meta = merged(waiting.meta, sighting)
        if GlobalStore.projects(waiting.with(meta:)).size < THRESHOLD
          return settled(Change.new(kind: :tagged, slug: waiting.slug), @store.write(waiting.path, meta, waiting.body))
        end

        activate(waiting, meta)
      end

      # @return [OpenLanes::Memory::Mirror::Change]
      def activate(waiting, meta)
        id = @store.next_id
        meta = meta.except("proposed").merge("id" => id, "status" => "active", "confirmed" => @today.call)
        change = settled(Change.new(kind: :activate, slug: waiting.slug, id:), @store.write(@store.lesson_path(id, waiting.slug), meta, waiting.body))
        @store.remove(waiting) if change.kind == :activate
        change
      end

      # @return [OpenLanes::Memory::Mirror::Change] +change+, or a refusal when +problem+ says why
      def settled(change, problem) = problem ? change.with(kind: :refuse, why: problem) : change

      # The record's meta with this project added to `projects:`, and its
      # sightings to `source:`. A plan's ordinal is per project too, so each
      # is prefixed with the project: `045.00` in two projects is two plans,
      # and {Lesson#confirmations} counts them as two.
      #
      # @return [Hash{String => Object}]
      def merged(meta, sighting)
        meta.merge("projects" => Array(meta["projects"]).grep(Hash) + [{ "project" => @project, "lesson" => sighting.id }],
          "source" => (Array(meta["source"]).grep(Hash) + sources_of(sighting)).uniq)
      end

      # @return [Array<Hash{String => String}>] the sighting's `source:`, each plan prefixed with the project
      def sources_of(sighting)
        Array(sighting.record.meta["source"]).grep(Hash).map { it.merge("plan" => "#{@project} #{it["plan"]}".strip) }
      end

      # @return [Boolean] whether this project is already one of +record+'s
      def tagged?(record) = GlobalStore.projects(record).include?(@project)

      # @return [OpenLanes::Memory::Candidate, nil]
      def find(records, sighting)
        key = title_key(sighting.record.meta["title"])
        records.find { (it.meta["slug"] || it.slug) == sighting.slug || title_key(it.meta["title"]) == key }
      end

      # @return [String] the title without case, punctuation or spacing
      def title_key(title) = title.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end
  end
end

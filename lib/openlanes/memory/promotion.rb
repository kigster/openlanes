# frozen_string_literal: true

module OpenLanes
  module Memory
    # The step that turns a waiting candidate into an active lesson, and it
    # is arithmetic, not judgement: no model is asked.
    #
    # - A candidate whose slug is an existing lesson's id, or the name its
    #   file was promoted under, is new evidence for that lesson: its sources
    #   are added and `confirmed:` moves to today. That is how a lesson
    #   compounds: each later plan that meets it again counts, and
    #   {Library#for} ranks by `confirmed`, so a lesson that keeps proving
    #   itself stays at the top of the prompt.
    # - A candidate seen in {THRESHOLD} plans, or approved by a person,
    #   becomes `lessons/L-NNNN-<slug>.md` with `status: active`.
    # - Anything else waits.
    #
    # It writes files in the working tree and nothing else. They reach an
    # agent only once a person has merged them: {Memory.library} reads
    # lessons from the default branch.
    class Promotion
      # Plans a candidate must be seen in before it is promoted unasked. One
      # plan's finding is an incident; the same finding on a second plan is a
      # pattern (docs/continuous-learning.md).
      THRESHOLD = 2

      # The ids this class mints.
      ID = /\AL-(\d{4,})\z/

      # One thing {#call} did, or with `commit: false` would do.
      #
      # @!attribute [r] kind
      #   @return [Symbol] `:promote`, `:confirm`, `:wait` or `:refuse`
      # @!attribute [r] path
      #   @return [String, nil] the lesson file written
      # @!attribute [r] why
      #   @return [String]
      Change = Data.define(:kind, :slug, :id, :path, :why)

      # @param inbox [OpenLanes::Memory::Inbox]
      # @param lessons_dir [String]
      # @param threshold [Integer]
      # @param today [#call] returns the current `Date`
      def initialize(inbox:, lessons_dir:, threshold: THRESHOLD, today: -> { Date.today })
        @inbox = inbox
        @lessons_dir = lessons_dir
        @threshold = threshold
        @today = today
      end

      # @param commit [Boolean] false previews: nothing is written
      # @return [Array<OpenLanes::Memory::Promotion::Change>] one per candidate, by slug
      def call(commit: true)
        lessons = existing
        taken = lessons.filter_map { it.meta["id"].to_s[ID, 1]&.to_i }
        @inbox.candidates.map do |candidate|
          draft = draft_for(candidate, lessons, taken)
          draft.is_a?(Change) ? draft : settle(draft, commit:)
        end
      end

      private

      # A lesson file about to be written: the candidate it comes from, and
      # everything the file will say.
      Draft = Data.define(:candidate, :kind, :id, :path, :meta, :body, :why)
      private_constant :Draft

      # @return [Array<OpenLanes::Memory::Candidate>] the lesson files, read as the inbox reads its own
      def existing = Inbox.new(dir: @lessons_dir).candidates

      # @param taken [Array<Integer>] the lesson numbers in use; a promotion adds its own
      # @return [Draft, OpenLanes::Memory::Promotion::Change] a change when the candidate waits
      def draft_for(candidate, lessons, taken)
        lesson = lessons.find { same?(it, candidate.slug) }
        return confirm(candidate, lesson) if lesson
        return wait(candidate) unless candidate.approved? || candidate.plans.size >= @threshold

        taken << ((taken.max || 0) + 1)
        promote(candidate, format("L-%04d", taken.last))
      end

      # @return [Boolean] whether +lesson+ is the one a candidate's slug names
      def same?(lesson, slug) = lesson.slug == slug || lesson.meta["id"] == slug || lesson.slug.end_with?("-#{slug}")

      # @return [OpenLanes::Memory::Promotion::Change]
      def wait(candidate)
        seen = candidate.plans.size
        Change.new(kind: :wait,
          slug: candidate.slug,
          id: nil,
          path: nil,
          why: "seen in #{seen} plan#{"s" unless seen == 1}, needs #{@threshold} or a person's approval")
      end

      # @return [Draft]
      def confirm(candidate, lesson)
        meta = lesson.meta.merge("source" => (lesson.sources + candidate.sources).uniq, "confirmed" => @today.call)
        Draft.new(candidate:,
          kind: :confirm,
          id: lesson.meta["id"].to_s,
          path: lesson.path,
          meta:,
          body: lesson.body,
          why: "seen again on #{candidate.plans.join(", ")}")
      end

      # @return [Draft]
      def promote(candidate, id)
        meta = candidate.meta.except("approved", "proposed").merge("id" => id, "status" => "active", "confirmed" => @today.call)
        why = candidate.approved? ? "approved by a person" : "seen in #{candidate.plans.size} plans: #{candidate.plans.join(", ")}"
        Draft.new(candidate:,
          kind: :promote,
          id:,
          path: File.join(@lessons_dir, "#{id}-#{candidate.slug}.md"),
          meta:,
          body: candidate.body,
          why:)
      end

      # Write the lesson and take the candidate out of the inbox, unless the
      # finished file would hold a secret: evidence merged from several plans
      # is scanned as a whole, since each part passed alone.
      #
      # @param draft [Draft]
      # @return [OpenLanes::Memory::Promotion::Change]
      def settle(draft, commit:)
        text = @inbox.render(draft.meta, draft.body)
        found = Secrets.scan(text).map(&:kind).uniq
        slug = draft.candidate.slug
        return Change.new(kind: :refuse, slug:, id: draft.id, path: nil, why: "looks like it holds #{found.join(", ")}") unless found.empty?

        write(draft, text) if commit
        Change.new(kind: draft.kind, slug:, id: draft.id, path: draft.path, why: draft.why)
      end

      # @return [void]
      def write(draft, text)
        FileUtils.mkdir_p(@lessons_dir)
        File.write(draft.path, text)
        @inbox.remove(draft.candidate.slug)
      end
    end
  end
end

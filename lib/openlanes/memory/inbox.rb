# frozen_string_literal: true

require "fileutils"
require "yaml"

module OpenLanes
  module Memory
    # `.openlanes/memory/inbox/`: lessons proposed and not yet active, one
    # file per slug. Nothing here reaches a prompt: {Library} reads
    # `lessons/` only, and a candidate says `status: candidate` besides.
    #
    # The harness is the only writer. A proposal is rendered as a lesson
    # file, read back through {Lesson.parse} so the inbox accepts exactly
    # what `lessons/` would, and scanned by {Secrets}; anything that fails
    # either is dropped with a reason and never touches the disk.
    class Inbox
      # What became of one proposal.
      #
      # @!attribute [r] status
      #   @return [Symbol] `:added`, `:confirmed` (already waiting; this plan
      #     is new evidence), `:known` (this plan already said so) or `:dropped`
      # @!attribute [r] reason
      #   @return [String, nil] why it was dropped
      Outcome = Data.define(:slug, :status, :reason)

      # @return [String]
      attr_reader :dir

      # @param dir [String] the inbox directory
      # @param today [#call] returns the current `Date`
      def initialize(dir:, today: -> { Date.today })
        @dir = dir
        @today = today
      end

      # @return [Array<OpenLanes::Memory::Candidate>] by slug; unreadable files are left out
      def candidates
        Folder.new(name: :inbox, dir:).entries.grep(Entry).filter_map { candidate(it) }
      end

      # @param slug [String]
      # @return [OpenLanes::Memory::Candidate, nil]
      def find(slug) = candidates.find { it.slug == slug }

      # Take one proposal from one plan.
      #
      # @param proposal [OpenLanes::Memory::Proposal]
      # @param plan [String] the ordinal it was learnt on
      # @return [OpenLanes::Memory::Inbox::Outcome]
      def add(proposal, plan:)
        slug = proposal.slug
        return drop(slug, "slug must be lower-case words joined by `-`") unless slug.match?(/\A[a-z0-9][a-z0-9-]{0,63}\z/i)

        waiting = find(slug)
        return confirm(waiting, proposal, plan) if waiting

        write(slug, meta_for(proposal, plan), proposal.body, added: :added)
      end

      # A person's word that a candidate is promoted whatever its count.
      #
      # @param slug [String]
      # @return [OpenLanes::Memory::Candidate, nil] nil when nothing waits under that slug
      def approve(slug)
        waiting = find(slug) or return nil
        File.write(waiting.path, render(waiting.meta.merge("approved" => true), waiting.body))
        find(slug)
      end

      # @param slug [String]
      # @return [void]
      def remove(slug)
        waiting = find(slug) and File.delete(waiting.path)
      end

      # @param meta [Hash{String => Object}]
      # @param body [String]
      # @return [String] a lesson file
      def render(meta, body) = "#{YAML.dump(meta)}---\n\n#{body.strip}\n"

      private

      # @return [OpenLanes::Memory::Candidate, nil]
      def candidate(entry)
        meta, body = Frontmatter.split(entry.text.dup.force_encoding(Encoding::UTF_8))
        Candidate.new(slug: File.basename(entry.path, ".md"), meta:, body: body.to_s.strip, path: entry.path)
      rescue Psych::Exception, ArgumentError
        nil
      end

      # @return [Hash{String => Object}]
      def meta_for(proposal, plan)
        { "id" => proposal.slug, "title" => proposal.title, "applies_to" => proposal.applies_to,
          "checked_by" => proposal.checked_by, "kind" => proposal.kind, "severity" => proposal.severity,
          "status" => "candidate", "proposed" => @today.call,
          "source" => [{ "plan" => plan.to_s, "finding" => proposal.finding }] }.compact
      end

      # The same lesson seen again: one more plan's evidence, and the words
      # first written stay as they were.
      #
      # @return [OpenLanes::Memory::Inbox::Outcome]
      def confirm(waiting, proposal, plan)
        return Outcome.new(slug: waiting.slug, status: :known, reason: nil) if waiting.plans.include?(plan.to_s)

        source = waiting.sources + [{ "plan" => plan.to_s, "finding" => proposal.finding }]
        write(waiting.slug, waiting.meta.merge("source" => source), waiting.body, added: :confirmed)
      end

      # @return [OpenLanes::Memory::Inbox::Outcome]
      def write(slug, meta, body, added:)
        text = render(meta, body)
        path = File.join(dir, "#{slug}.md")
        problem = problem_with(text, path)
        return drop(slug, problem) if problem

        FileUtils.mkdir_p(dir)
        return drop(slug, "#{path} is a symlink") if File.symlink?(path)

        File.write(path, text)
        Outcome.new(slug:, status: added, reason: nil)
      end

      # @return [String, nil] why +text+ may not be written
      def problem_with(text, path)
        found = Secrets.scan(text)
        return "looks like it holds #{found.map(&:kind).uniq.join(", ")}" unless found.empty?

        Lesson.parse(Entry.new(path:, text:, cite: path), scope: :project)
        nil
      rescue Lesson::Invalid => e
        e.message.delete_prefix("#{path}: ")
      end

      # @return [OpenLanes::Memory::Inbox::Outcome]
      def drop(slug, reason) = Outcome.new(slug:, status: :dropped, reason:)
    end
  end
end

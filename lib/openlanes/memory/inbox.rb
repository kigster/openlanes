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
      # @!attribute [r] check
      #   @return [Symbol, nil] which check dropped it: `:format`, `:slug`,
      #     `:secrets`, `:instructions`, `:lesson` or `:path`
      # @!attribute [r] text
      #   @return [String, nil] the file written, or on a dry run the file that would be
      Outcome = Data.define(:slug, :status, :reason, :check, :text) do
        def initialize(check: nil, text: nil, **) = super
      end

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
      # A plan may be absent: `openlanes memory propose` from an agent that
      # works outside a run. Such a sighting carries its finding and no plan,
      # so it counts toward nothing in {Promotion} until a plan meets it.
      #
      # @param proposal [OpenLanes::Memory::Proposal]
      # @param plan [String, nil] the ordinal it was learnt on
      # @param dry_run [Boolean] true checks and renders, and writes nothing
      # @return [OpenLanes::Memory::Inbox::Outcome]
      def add(proposal, plan:, dry_run: false)
        slug = proposal.slug
        return drop(slug, "slug must be lower-case words joined by `-`", :slug) unless slug.match?(/\A[a-z0-9][a-z0-9-]{0,63}\z/i)

        plan = plan.to_s.strip
        waiting = find(slug)
        return confirm(waiting, proposal, plan, dry_run) if waiting

        write(slug, render(meta_for(proposal, plan), proposal.body), added: :added, dry_run:)
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
          "source" => [sighting(plan, proposal)] }.compact
      end

      # @return [Hash{String => String}] `plan` left out when there is none
      def sighting(plan, proposal) = { "plan" => (plan unless plan.empty?), "finding" => proposal.finding }.compact

      # The same lesson seen again: one more plan's evidence, and the words
      # first written stay as they were.
      #
      # @return [OpenLanes::Memory::Inbox::Outcome]
      def confirm(waiting, proposal, plan, dry_run)
        return Outcome.new(slug: waiting.slug, status: :known, reason: nil) if known?(waiting, proposal, plan)

        source = waiting.sources + [sighting(plan, proposal)]
        write(waiting.slug, render(waiting.meta.merge("source" => source), waiting.body), added: :confirmed, dry_run:)
      end

      # A plan that already said so says nothing new; without a plan, the
      # same finding again is the same sighting, not one more.
      def known?(waiting, proposal, plan)
        return waiting.plans.include?(plan) unless plan.empty?

        waiting.sources.any? { it["plan"].to_s.empty? && it["finding"] == proposal.finding }
      end

      # @return [OpenLanes::Memory::Inbox::Outcome]
      def write(slug, text, added:, dry_run: false)
        path = File.join(dir, "#{slug}.md")
        check, problem = problem_with(text, path)
        return drop(slug, problem, check) if problem
        return drop(slug, "#{path} is a symlink", :path) if File.symlink?(path)
        return Outcome.new(slug:, status: added, reason: nil, text:) if dry_run

        FileUtils.mkdir_p(dir)
        File.write(path, text)
        Outcome.new(slug:, status: added, reason: nil, text:)
      end

      # Words a lesson has no business saying: an order to the agents that
      # will read it, rather than a fact about the project. Every lesson
      # reaches a prompt, so a candidate that reads as one is dropped here,
      # deterministically, before a person ever has to spot it.
      INSTRUCTIONS = [
        /\b(ignore|disregard|forget|override)\b.{0,40}\b(previous|prior|above|earlier|other|your|all)\b.{0,40}\b(instructions?|prompts?|rules?|checks?|findings?)\b/i,
        /\b(approve|merge)\b.{0,30}\b(every|all|any)\b.{0,30}\b(pull requests?|PRs?|plans?|changes?)\b/i,
        /\byou are now\b|\bsystem prompt\b|\bnew instructions\b/i
      ].freeze
      private_constant :INSTRUCTIONS

      # @return [Array(Symbol, String), nil] the check that refused +text+, and why
      def problem_with(text, path)
        found = Secrets.scan(text)
        return [:secrets, "looks like it holds #{found.map(&:kind).uniq.join(", ")}"] unless found.empty?
        return [:instructions, "reads as an instruction to other agents, not a lesson"] if INSTRUCTIONS.any? { text.match?(it) }

        Lesson.parse(Entry.new(path:, text:, cite: path), scope: :project)
        nil
      rescue Lesson::Invalid => e
        [:lesson, e.message.delete_prefix("#{path}: ")]
      end

      # @return [OpenLanes::Memory::Inbox::Outcome]
      def drop(slug, reason, check) = Outcome.new(slug:, status: :dropped, reason:, check:)
    end
  end
end

# frozen_string_literal: true

require "dry/monads"
require "fileutils"

module OpenLanes
  module Lifecycle
    # Mints new plan folders. Backs `/spec-create`.
    #
    # Every failure is a `Failure`, never an exception: creating a folder is the
    # one place a typo becomes permanent, so the caller is made to look.
    class Creator
      include Dry::Monads[:result]

      # The state a new plan opens in — a specification and nothing else yet.
      DEFAULT_STATUS = :new

      # The state a retroactive plan is born in: the work is live, but it has
      # neither a specification nor a plan.
      RETROACTIVE_STATUS = :retroactive

      # @param dir [String] the `.plans` directory
      def initialize(dir:)
        @dir = File.expand_path(dir)
      end

      # @return [String] the `.plans` directory
      attr_reader :dir

      # Create a plan folder.
      #
      # @param words [Array<String>] the topic; becomes the slug
      # @param after [String, nil] anchor for a retroactive plan, e.g. "002"
      # @param status [String, Symbol, nil] override the default state
      # @param prs [Array<Hash>, nil] pull requests to record, already fetched;
      #   their presence is what makes the folder 🕰️ Retroactive rather than ⚪️
      # @return [Dry::Monads::Result] Success(absolute path) or Failure(message)
      def create(words:, after: nil, status: nil, prs: nil)
        resolved = resolve_status(status, after) or
          return Failure("unknown status: #{status}")

        slug = self.class.slugify(words)
        return Failure("the topic produced an empty slug") if slug.empty?

        ordinal = after ? retroactive_ordinal(after) : Plans::Ordinal.next_major(existing)
        return ordinal if ordinal.is_a?(Dry::Monads::Result)

        build(ordinal, resolved, slug).fmap { |path| record_pull_requests(path, prs) }
      rescue OpenLanes::Error => e
        Failure(e.message)
      end

      # Archived, deferred and abandoned plans keep their numbers (N3), so a
      # number that lives only in `archive/` is still taken.
      #
      # @return [Array<OpenLanes::Plans::Ordinal>] every number already taken
      def existing = @existing ||= Plans::Tree.new(dir:).taken

      # How many words of an idea name its plan.
      TOPIC_WORDS = 8

      # The words a free-form idea's plan is named after: a frontmatter
      # `title:`, else its first line, a heading's `#` marks dropped.
      #
      # Taking the first words of the raw text named the minesweeper trial's
      # plan `minesweeper-minesweeper-is-played-on-a-grid`: the idea opened
      # with `# Minesweeper` and then a paragraph starting with the same
      # word, and the heading's `#` was dropped while its word was kept.
      #
      # @param idea [String] Markdown, as the page's idea dialog sends it
      # @return [Array<String>] at most {TOPIC_WORDS} words, possibly none
      def self.topic(idea)
        meta, body = begin
          Frontmatter.split(idea.to_s)
        rescue Psych::Exception
          [{}, idea.to_s.sub(Frontmatter::PATTERN, '\\2')]
        end
        title = meta["title"].to_s.strip
        line = title.empty? ? body.lines.map(&:strip).find { !it.empty? }.to_s : title
        line.sub(/\A\#{1,6}\s+/, "").split.first(TOPIC_WORDS)
      end

      # Turn free text into the kebab tail of a folder name.
      #
      # @param words [Array<String>, String]
      # @return [String] possibly empty, which the caller must reject
      def self.slugify(words)
        Array(words).join(" ").downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      end

      private

      # @param status [String, Symbol, nil]
      # @param after [String, nil]
      # @return [OpenLanes::Plans::Status, nil]
      def resolve_status(status, after)
        return OpenLanes::Plans.status(status) if status

        Plans::STATUS_BY_KEY.fetch(after ? RETROACTIVE_STATUS : DEFAULT_STATUS)
      end

      # @param after [String]
      # @return [OpenLanes::Plans::Ordinal, Dry::Monads::Result]
      def retroactive_ordinal(after)
        anchor = Plans::Ordinal.parse(after) or return Failure("not a plan number: #{after}")

        unless existing.any? { |o| o.major == anchor.major }
          return Failure("no plan #{format("%03d", anchor.major)} to anchor against — " \
                         "a retroactive plan names the plan its work landed after")
        end

        Plans::Ordinal.next_minor(existing, major: anchor.major)
      end

      # Write the pull requests the folder was created from, so 🕰️ Retroactive
      # is justified the moment the folder exists — that state means "the work is
      # live and undocumented", and it is the recorded pull requests that make
      # the first half of that true.
      #
      # @param path [String] the new folder
      # @param prs [Array<Hash>, nil]
      # @return [String] the path, unchanged
      def record_pull_requests(path, prs)
        return path if prs.nil? || prs.empty?

        File.write(File.join(path, Plans::PullRequests::FILENAME), Plans::PullRequests.render(prs))
        path
      end

      # @param ordinal [OpenLanes::Plans::Ordinal]
      # @param status [OpenLanes::Plans::Status]
      # @param slug [String]
      # @return [Dry::Monads::Result]
      def build(ordinal, status, slug)
        target = File.join(dir, OpenLanes::Plans.plan_dirname(ordinal, status, slug))
        return Failure("already exists: #{File.basename(target)}") if File.exist?(target)

        FileUtils.mkdir_p(target)
        Plans::PlanState.for(target).state!(status.key)
        @existing = nil
        Success(target)
      end
    end
  end
end

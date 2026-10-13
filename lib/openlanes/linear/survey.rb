# frozen_string_literal: true

module OpenLanes
  module Linear
    # What a team already has in Linear, set against what `.plans` holds.
    #
    # This exists because the import cannot see Linear at all — that is the
    # property that makes its dry run trustworthy — and the cost of that
    # property is a blind spot: a plan whose project someone already made by
    # hand looks, from disk, exactly like a plan that has none. Proposing to
    # create it would quietly produce a second project beside the first.
    #
    # So the reconciliation is its own read-only command rather than something
    # smuggled into the import. It answers one question — *is anything here
    # already in Linear under a different name?* — and answers it by showing
    # both lists rather than by guessing.
    class Survey
      # How a project and a plan were found to be the same thing.
      #
      # Both rules are exact after normalising; neither is fuzzy. A near-match
      # is reported as a near-match, because a project silently adopted by the
      # wrong plan is worse than one nobody adopted at all.
      Match = Data.define(:project, :subject, :rule) do
        # @return [String]
        def why = { ordinal: "its name carries the plan number", slug: "its name is the plan's slug" }.fetch(rule)
      end

      # @param tree [OpenLanes::Plans::Tree]
      # @param projects [Array<Hash>] `{"id", "name", "url", "status"}` from {API#projects}
      def initialize(tree:, projects:)
        @tree = tree
        @projects = projects
      end

      # @return [Array<Hash>] every project, as Linear reports it
      attr_reader :projects

      # @return [Array<OpenLanes::Linear::Survey::Match>]
      def matches = @matches ||= projects.filter_map { |project| match_for(project) }

      # Projects that correspond to no plan. Usually the team's real,
      # hand-curated projects — the ones an import has no business touching.
      #
      # @return [Array<Hash>]
      def unmatched = projects - matches.map(&:project)

      # Plans with no project. An import would create one for each.
      #
      # @return [Array<OpenLanes::Plans::Subject>]
      def uncovered = tree.subjects - matches.map(&:subject)

      # Projects whose name shares the plan's words without matching either
      # rule, best first.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<Hash>]
      def near(subject) = scored(subject).map(&:first)

      # The best guess at which project a plan belongs under, for
      # `--auto-assign`, with the number of words it agreed on.
      #
      # One shared word is not evidence — half these plans mention "tax" — so
      # a guess needs two. Even then it is reported as a guess wherever it
      # appears, because `plaid-integration` matching `Plaid Connectivity` is
      # obvious to a person and, to this, indistinguishable from
      # `tax-engine-consolidation` matching `Tax Law Engine`, which is wrong.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array(Hash, Integer), nil] the project and its score
      def guess(subject)
        best, score = scored(subject).first
        return nil unless best && score >= 2

        [best, score]
      end

      # Projects with nothing written about them.
      #
      # A name is three or four words and half of them are the company's. What
      # makes a plan recognisably one project's business rather than another's
      # is the sentence saying what the project is for, and where that sentence
      # is missing there is nothing to match a specification against.
      #
      # @return [Array<Hash>]
      def undescribed = projects.reject { |p| described?(p) }

      # @param project [Hash]
      # @return [Boolean]
      def described?(project) = !prose(project).strip.empty?

      # Find one project by whatever the user had to hand: its URL, its name,
      # or its id. A URL is the thing you can actually copy out of Linear.
      #
      # @param reference [String]
      # @return [Hash]
      # @raise [OpenLanes::Error] when nothing matches it
      def project(reference)
        wanted = reference.to_s.strip
        found = projects.find { |p|
          p["url"].to_s.casecmp?(wanted) || p["name"].to_s.casecmp?(wanted) ||
            p["id"] == wanted || p["url"].to_s.end_with?("/#{slugify(wanted)}")
        }
        return found if found

        raise Error,
          "no project matches #{reference.inspect}. This team has:\n" +
          projects.map { |p| "  #{p["name"]}\n    #{p["url"]}" }.join("\n")
      end

      private

      # @return [OpenLanes::Plans::Tree]
      attr_reader :tree

      # @param project [Hash]
      # @return [OpenLanes::Linear::Survey::Match, nil]
      def match_for(project)
        name = project["name"].to_s

        by_ordinal = tree.subjects.find { |s| name.include?(s.feature.ordinal.to_s) }
        return Match.new(project:, subject: by_ordinal, rule: :ordinal) if by_ordinal

        by_slug = tree.subjects.find { |s| slugify(name) == s.feature.slug }
        Match.new(project:, subject: by_slug, rule: :slug) if by_slug
      end

      # Every project that shares a word with this plan, best first.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<Array(Hash, Integer)>]
      def scored(subject)
        wanted = plan_words(subject)
        return [] if wanted.empty?

        projects.filter_map { |p|
          overlap = (project_words(p) & wanted).size
          [p, overlap] if overlap.positive?
        }.sort_by { |_, overlap| -overlap }
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<String>]
      def plan_words(subject)
        words(subject.feature.slug) | words(slugify(subject.feature.title)) |
          words(slugify(subject.goal.join(" ")))
      end

      # @param project [Hash]
      # @return [Array<String>]
      def project_words(project)
        (@project_words ||= {})[project["id"]] ||=
          words(slugify(project["name"])) | words(slugify(prose(project)))
      end

      # Whatever the project says about itself. Linear keeps a short line and a
      # long document and a team uses whichever it uses.
      #
      # @param project [Hash]
      # @return [String]
      def prose(project) = "#{project["description"]} #{project["content"]} #{project["summary"]}"

      # @param text [String]
      # @return [String]
      def slugify(text) = text.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")

      # Words too common to carry a match on their own.
      NOISE = %w[the a an and or of to for app web spec plan].freeze

      # @param slug [String]
      # @return [Array<String>]
      def words(slug) = slug.to_s.split("-").reject { |w| w.length < 3 || NOISE.include?(w) }
    end
  end
end

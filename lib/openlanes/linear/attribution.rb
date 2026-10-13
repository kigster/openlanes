# frozen_string_literal: true

module OpenLanes
  module Linear
    # Which plan a pull request belongs to, when its title does not say.
    #
    # `resync prs` puts an `[NNN.MM]` on every title it can resolve, and most
    # of them resolve. What is left is the tail: work that shipped before the
    # convention existed, or from a branch named after nothing in particular.
    # Those pull requests are real work with no home, and dropping them means
    # the issues that stand for a plan are missing pieces of it.
    #
    # The rule is word overlap between the pull request's title and the
    # folder's name. It works here, where it did not work for matching plans
    # to projects, because the candidates are different: a folder slug is
    # `ledger-carryforward-vintages`, three specific words about one thing,
    # and there are twenty of them to choose between. A project is called
    # "US Tax Law: Self Contained Ruby Gem" and there are four.
    #
    # It is still a guess, and it says so. A tie is refused rather than broken,
    # because two folders matching equally well is evidence that neither is
    # right rather than a reason to pick the first.
    class Attribution
      # One pull request, placed.
      #
      # @!attribute [r] pull
      #   @return [OpenLanes::Plans::PullRequest]
      # @!attribute [r] subject
      #   @return [OpenLanes::Plans::Subject, nil] nil when nothing matched
      # @!attribute [r] score
      #   @return [Integer] words the title and the folder name shared
      # @!attribute [r] rivals
      #   @return [Array<String>] folders that matched equally well
      Placed = Data.define(:pull, :subject, :score, :rivals, :widened) do
        # @return [Boolean]
        def placed? = !subject.nil?

        # @return [String]
        def percent = "#{(score * 100).round}%"

        # @return [String] where the matching words came from
        def source = widened ? "title and description" : "title"

        # @return [String]
        def why
          return "matched no folder at all" if subject.nil? && score.zero?
          return "#{percent} of a folder name is not enough" if subject.nil? && rivals.empty?
          # `rivals` already holds every tied folder — there is no winner to
          # add back in, and `+ 1` here once reported a two-way tie as three.
          return "#{rivals.size} folders matched equally well (#{percent})" if subject.nil?

          "#{source}: covers #{percent} of the folder name"
        end
      end

      # Words too common in this domain to carry a match on their own. Every
      # plan in a tax engine says "tax"; a pull request that says it too has
      # told you nothing.
      # How much of a folder's name a title must cover to claim it.
      FLOOR = 0.5

      # And how much a description must cover, which is more.
      #
      # A title is written to say what the change is. A description is written
      # to get the change reviewed, and it opens with whatever this repository
      # puts at the top of every one of them — a stacking note, a diff
      # summary, a checklist. Read at the same bar as a title it produced two
      # placements here and both were wrong, one of them on the word
      # "documents" inside "diff includes nineteen documents".
      WIDER_FLOOR = 0.75

      # Words, not just a fraction. Half of a two-word folder name is one
      # word, which is the case that was already established as too thin —
      # "core" alone claiming `deterministic-core-and-as-of`.
      MINIMUM_WORDS = 3

      NOISE = %w[the and for with from into that this add adds added fix fixes
                 update updates use uses spec plan pull request pr tax app web api].freeze

      # @param tree [OpenLanes::Plans::Tree]
      def initialize(tree:)
        @tree = tree
      end

      # How much of a pull request's description to read when its title was
      # not enough. The opening sentence or two of a description says what the
      # change is for; further down it turns into checklists, test plans and
      # generated tables, which are the same words on every pull request in
      # the repository and match everything equally.
      OPENING_WORDS = 20

      # @param pulls [Array<OpenLanes::Plans::PullRequest>] the ones with no number
      # @param bodies [Hash{String => String}] descriptions, by pull request number
      # @return [Array<OpenLanes::Linear::Attribution::Placed>]
      def call(pulls, bodies: {})
        pulls.map do |pull|
          found = place(pull, words(pull.title))
          next found if found.placed?

          # Second pass. A title is a headline and sometimes says nothing
          # useful — "Add the Drake reference-return worklist" names a vendor
          # rather than the work. The description usually opens by saying what
          # the change is actually about.
          opening = opening_words(bodies[pull.number.to_s])
          next found if opening.empty?

          wider = place(pull, words(pull.title) | opening, floor: WIDER_FLOOR)
          wider.placed? ? wider.with(widened: true) : found
        end
      end

      # @param body [String, nil]
      # @return [Array<String>]
      def opening_words(body)
        text = body.to_s
                   .gsub(/<!--.*?-->/m, "")
                   .gsub(/```.*?```/m, "")
                   .gsub(/^\s*[-*|#>]+/, " ")
        words(text.split(/\s+/).first(OPENING_WORDS * 3).join(" ")).first(OPENING_WORDS)
      end

      private

      # @return [OpenLanes::Plans::Tree]
      attr_reader :tree

      # @param pull [OpenLanes::Plans::PullRequest]
      # @param wanted [Array<String>] the words to match on
      # @param floor [Float] how much of a folder name is enough
      # @return [OpenLanes::Linear::Attribution::Placed]
      def place(pull, wanted, floor: FLOOR)
        return Placed.new(pull:, subject: nil, score: 0.0, rivals: [], widened: false) if wanted.empty?

        ranked = tree.subjects.filter_map { |s|
          overlap = shared(folder_words(s), wanted)
          [s, overlap] if overlap.positive?
        }.sort_by { |_, overlap| -overlap }

        best, score = ranked.first

        # One word in common is not evidence. "Add year-keyed tax rules" shares
        # "rules" with `rules-retirement-and-engine-convergence` and has
        # nothing to do with it.
        enough = best && score >= floor && (score * folder_words(best).size).round >= MINIMUM_WORDS
        return Placed.new(pull:, subject: nil, score: score.to_f, rivals: [], widened: false) unless enough

        tied = ranked.select { |_, overlap| overlap == score }
        return Placed.new(pull:, subject: best, score:, rivals: [], widened: false) if tied.one?

        Placed.new(pull:, subject: nil, score:, rivals: tied.map { |s, _| s.feature.dirname }, widened: false)
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<String>]
      def folder_words(subject)
        (@folder_words ||= {})[subject.feature.path] ||=
          words(subject.feature.slug.tr("-", " ")) | words(subject.feature.title)
      end

      # @param text [String]
      # @return [Array<String>]
      def words(text)
        text.to_s.downcase.gsub(/[^a-z0-9]+/, " ").split
            .reject { |w| w.length < 4 || NOISE.include?(w) }.uniq
      end

      # How much of a folder's name a pull request title actually said.
      #
      # A pull request said `signed_off` where its folder says `sign-off`, and
      # `vintages` where the folder says `vintage`. Compared literally those
      # are strangers, and the first cost a placement a human makes instantly
      # — one a later, numbered pull request went on to prove correct.
      #
      # Matching on a shared prefix rather than by stripping suffixes, because
      # stripping is destructive and gets it wrong in both directions:
      # `corpus` is not a plural, and turning it into `corpu` reads as a typo
      # in every diagnostic that prints it.
      #
      # @param folder [Array<String>]
      # @param title [Array<String>]
      # @return [Float] 0.0 to 1.0
      def shared(folder, title) = Fuzzy.coverage(folder, title)
    end
  end
end

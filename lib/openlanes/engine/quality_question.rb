# frozen_string_literal: true

module OpenLanes
  module Engine
    # R4's question, `desired_codebase_quality`, put to a person once per
    # project: on the first pull request labelled `review-passed`
    # while `.openlanes.yml` has no key. It hangs on the plan whose pull
    # request raised it, kept in that plan's `state.json` so it survives a
    # restart, and every other plan waiting on the same answer stays 👀
    # without asking again. The answer is written into `.openlanes.yml`,
    # after which nothing asks.
    module QualityQuestion
      # The question's name on its plan, as `X<n>` is an extension's.
      NAME = "Q1"

      # R4's wording, verbatim where it fits a card.
      HEADING = "Please indicate the desired quality of the codebase"

      # @return [String]
      BODY = "This affects the severity of items found during review that will require rework. " \
             "Critical blocking issues or security issues identified during review will be addressed regardless."

      # One choice, the letter the page sends back and the key it writes.
      #
      # @!attribute [r] letter
      #   @return [String]
      # @!attribute [r] quality
      #   @return [Symbol] one of {Config::QUALITIES}
      # @!attribute [r] label
      #   @return [String]
      Choice = Data.define(:letter, :quality, :label)

      # @return [Array<Choice>] R4's three levels (plan 035), strictest first,
      #   in the words the spec gives them: the terminal, the page and
      #   `decisions.md` all read these, so they cannot drift apart
      CHOICES = [
        Choice.new(letter: "a",
          quality: :high,
          label: "high: the highest quality software design, modularity, low inter-module coupling, high " \
                 "intra-module cohesion, design patterns, events, immutability and functional programming, at the " \
                 "cost of slower delivery, more rounds per plan and high standards for accepting the review. SOLID " \
                 "classes and maximum reuse in OO code; the most sophisticated UI. A \"review-passed\" PR " \
                 "returns to developers."),
        Choice.new(letter: "b",
          quality: :standard,
          label: "standard: a reasonable middle ground. Similar modularity and full test coverage, but less strict on " \
                 "SOLID, immutability and functional programming; likely fewer rounds and faster delivery. A " \
                 "\"review-passed\" PR returns to developers."),
        Choice.new(letter: "c",
          quality: :mvp,
          label: "mvp: the fastest and least designed codebase, for MVPs and prototypes, not for software with paying " \
                 "customers. Cheapest in AI tokens, most likely to have bugs, and a less sophisticated UI. A " \
                 "\"review-passed\" PR is accepted, as it has no blocking issues.")
      ].freeze

      # Where the answer is written down beside the plans, with every option
      # it was chosen from (plan 035).
      DECISIONS = "decisions.md"

      module_function

      # Ask, unless some plan in the same tree already has the question open.
      #
      # @param plan_dir [String] the asking plan's folder
      # @param at [Time]
      # @return [Boolean] whether this plan holds the open question
      def ask!(plan_dir, at: Clock::System.now)
        holder = open_in(File.dirname(plan_dir))
        return holder == plan_dir if holder

        Plans::PlanState.for(plan_dir).ask_quality!(at:)
        true
      end

      # @param plans_dir [String]
      # @return [String, nil] the folder of the plan whose question is open
      def open_in(plans_dir)
        Dir.glob(File.join(plans_dir, "*", Plans::PlanState::FILENAME)).map { File.dirname(it) }.find do |dir|
          ask = Plans::PlanState.for(dir).quality_ask
          ask && !ask.key?("settled_at")
        end
      end

      # The open question on this plan, as the page's `Question`s.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param plan [OpenLanes::Plans::PlanState]
      # @return [Array<Hash>] empty unless this plan holds it, unanswered
      def questions(subject, plan)
        ask = plan.quality_ask
        return [] if ask.nil? || ask.key?("settled_at")

        [{ id:       "#{subject.feature.ordinal}/#{NAME}",
           number:   1,
           kind:     "quality",
           heading:  HEADING,
           body:     BODY,
           agent:    nil,
           owner:    "product",
           options:  CHOICES.map do |choice|
             { letter: choice.letter, label: choice.label, recommended: choice.quality == Config::QUALITIES.first,
               answer: "#{choice.letter}) #{choice.label}" }
           end,
           held:     false,
           asked_at: ask["asked_at"] }]
      end

      # Settle the question and write the key, unless the file has one by now.
      #
      # @param plan_dir [String]
      # @param letter [String] "a", "b" or "c"
      # @param by [String]
      # @param root [String] the project root, where `.openlanes.yml` lives
      # @param at [Time]
      # @return [Symbol, nil] the quality chosen; nil when the question was not open
      # @raise [ArgumentError] on a letter that is not one of {CHOICES}
      def answer!(plan_dir, letter, by:, root:, at: Clock::System.now)
        choice = CHOICES.find { it.letter == letter.to_s.downcase } or
          raise ArgumentError, "#{letter} is not one of #{CHOICES.map { "#{it.letter})" }.join(", ")}"
        Plans::PlanState.for(plan_dir).settle_quality_ask!(answer: choice.quality, by:, at:) or return nil

        write_key(root, choice.quality)
        record(File.dirname(plan_dir), choice.quality, by:, at:)
        choice.quality
      end

      # The answer given on a terminal at the start of a run (plan 035):
      # the same key and `decisions.md` entry as {.answer!}, and a question
      # an earlier run left open on the page is settled with it, so the
      # page stops asking what the terminal already answered.
      #
      # @param root [String] the project root, where `.openlanes.yml` lives
      # @param plans_dir [String]
      # @param quality [Symbol] one of {Config::QUALITIES}
      # @param by [String]
      # @param at [Time]
      # @return [Symbol] the quality
      def settle!(root:, plans_dir:, quality:, by:, at: Time.now)
        holder = open_in(plans_dir)
        Plans::PlanState.for(holder).settle_quality_ask!(answer: quality, by:, at:) if holder
        write_key(root, quality)
        record(plans_dir, quality, by:, at:)
        quality
      end

      # Appended rather than rewritten through {Config#to_yaml}, which
      # would drop the comments a person keeps in the file.
      #
      # @return [void]
      def write_key(root, quality)
        path = File.join(root, Config::FILE)
        return unless Config.load(root).quality_unset?

        text = File.file?(path) ? File.read(path, encoding: "UTF-8") : ""
        text += "\n" unless text.empty? || text.end_with?("\n")
        File.write(path, "#{text}desired_codebase_quality: #{quality}\n")
      end

      # Append the answer to `decisions.md` in the plans directory, under the
      # three options it was picked from, so a later reader sees what each
      # level promised and not just its name.
      #
      # @param plans_dir [String]
      # @param quality [Symbol] one of {Config::QUALITIES}
      # @param by [String]
      # @param at [Time]
      # @return [String] the file's path
      def record(plans_dir, quality, by:, at: Time.now)
        path = File.join(plans_dir, DECISIONS)
        text = File.file?(path) ? File.read(path, encoding: "UTF-8") : "# Decisions\n"
        text += "\n" unless text.end_with?("\n")
        File.write(path, "#{text}\n#{entry(quality, by:, at:)}")
        path
      end

      # @return [String] one `decisions.md` section
      def entry(quality, by:, at:)
        options = CHOICES.map { "#{it.letter}) #{it.label}#{" **(chosen)**" if it.quality == quality}" }
        <<~MARKDOWN
          ## desired_codebase_quality: #{quality}

          #{HEADING}. Decided by #{by} on #{at.strftime("%Y-%m-%d")}, written to `#{Config::FILE}`.

          #{options.join("\n\n")}
        MARKDOWN
      end
    end
  end
end

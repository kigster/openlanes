# frozen_string_literal: true

module OpenLanes
  module Plans
    # The judgement calls a rebase resolver left under `## Rebase decisions`
    # in `plan.md` (036.00).
    #
    # bb8-resolver writes them and palpatine-risk-assessor rules on them, so
    # this is the one place that knows the syntax, and {KINDS} is the one list
    # both prompts quote. An entry is a list item; a judgement call carries a
    # tag in square brackets and the answer a person gave:
    #
    #   ## Rebase decisions
    #
    #   - [refactor-collision] lib/x.rb: main extracted the helper we patched; re-applied the guard there. Answer: unanswered
    #   - lib/y.rb: kept both imports.
    #
    # The second line is an ordinary resolution: untagged, so it asks nobody
    # anything. A tagged entry with no `Answer:` counts as unanswered, since
    # a call nobody looked at is exactly the one palpatine must not merge.
    module RebaseDecisions
      # The judgement calls that need a person: the same thing built twice, a
      # refactor that landed under our change, and a fork in behaviour.
      KINDS = %w[duplicate-implementation refactor-collision semantic-fork].freeze

      # What a person may answer. Only `confirmed` and `overridden` clear it.
      ANSWERS = %i[unanswered confirmed overridden].freeze

      # The shape both prompts quote, so the resolver writes what this reads.
      FORMAT = "- [<kind>] <file>: <what you kept, what you dropped, why>. Answer: unanswered"

      HEADING = /\A##\s+Rebase decisions\s*\z/i
      ITEM = /\A\s*(?:[-*+]|\d+\.)\s+(?<text>.+)\z/
      TAG = /\A\[(?<kind>[a-z-]+)\]\s*/
      ANSWER = /\bAnswer:\s*\**(?<answer>unanswered|confirmed|overridden)\b/i

      # One entry under the heading.
      #
      # @!attribute [r] kind
      #   @return [String, nil] one of {KINDS}, or nil for an untagged entry
      # @!attribute [r] answer
      #   @return [Symbol, nil] one of {ANSWERS}, or nil for an untagged entry
      # @!attribute [r] text
      #   @return [String] the entry without its tag
      Entry = Data.define(:kind, :answer, :text) do
        # @return [Boolean] whether this is a judgement call at all
        def tagged? = !kind.nil?

        # @return [Boolean] whether a person still has to look at it
        def unanswered? = answer == :unanswered

        # @return [String] the line as a prompt quotes it
        def to_s = tagged? ? "[#{kind}] #{text} (#{answer})" : text
      end

      class << self
        # @param plan_md [String] the contents of `plan.md`
        # @return [Array<Entry>] every entry under every `## Rebase decisions`, in order
        def parse(plan_md)
          items(plan_md.to_s).map { entry(it) }
        end

        # @param plan_md [String]
        # @return [Array<Entry>] the tagged entries no person has confirmed or overridden
        def unanswered(plan_md) = parse(plan_md).select(&:unanswered?)

        private

        # List items under the heading, a continuation line folded into the
        # item above it. A later `##` heading ends the section; another
        # `## Rebase decisions`, from a later rebase, starts it again.
        #
        # @return [Array<String>]
        def items(markdown)
          inside = false
          markdown.each_line.with_object([]) do |line, found|
            line = line.chomp
            if line.start_with?("## ") || line.match?(HEADING)
              inside = line.match?(HEADING)
            elsif inside && (m = ITEM.match(line))
              found << m[:text].strip
            elsif inside && found.any? && line.match?(/\A\s+\S/)
              found[-1] = "#{found[-1]} #{line.strip}"
            end
          end
        end

        # A tag outside {KINDS} is not a judgement call this harness knows,
        # so it reads as untagged rather than inventing a fourth kind.
        #
        # @return [Entry]
        def entry(text)
          tag = TAG.match(text)
          return Entry.new(kind: nil, answer: nil, text:) unless tag && KINDS.include?(tag[:kind])

          rest = text.delete_prefix(tag[0])
          said = ANSWER.match(rest)
          answer = said ? said[:answer].downcase.to_sym : :unanswered
          Entry.new(kind: tag[:kind], answer:, text: rest)
        end
      end
    end
  end
end

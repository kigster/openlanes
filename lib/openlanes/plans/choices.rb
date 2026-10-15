# frozen_string_literal: true

module OpenLanes
  module Plans
    # A question for a person, read as D3 shapes it: a short context paragraph,
    # then lettered options `a)`, `b)`, `c)`, one of them recommended. The page
    # draws a button per option, and `openlanes unblock` would offer the same
    # ones, so both read them here rather than each guessing from the prose.
    #
    # Agents are told to write only that shape, but files written before D3,
    # and agents that drift, use others. {.parse} reads them forgivingly:
    #
    # - lettered: `a)`, `(a)` or `a.` at the start of a line, or `a)` and
    #   `(a)` inline, the way agents actually run a whole choice into one
    #   paragraph; bullet-prefixed or bold-wrapped (`- **a)**`) alike
    # - numbered: `1.`, `1)` or `Option 1:` at the start of a line
    # - the W30 mark, `answers: yes, no`, which reads as `a) yes` `b) no`
    #
    # It is pure: text in, a value out, no file and no network. Whether the
    # text really asks the reader to choose is a judgement the parser cannot
    # make about a numbered list of steps already done, which is why the
    # snapshot can ask {Live::ChoiceJudge} as well.
    #
    # @example
    #   choices = Plans::Choices.parse("Rebase or merge?\n\na) Rebase (Recommended)\nb) Merge")
    #   choices.context                 # => "Rebase or merge?"
    #   choices.options.map(&:answer)   # => ["a) Rebase", "b) Merge"]
    #   choices.recommended.letter      # => "a"
    class Choices < Data.define(:context, :options)
      # The text the person's choice sends back to the agent, beside how the
      # option is shown. A yes/no option answers with the bare word, as W30
      # promised agents ("branch on the word"); every other answers with its
      # letter and label, so the agent can match either.
      #
      # @!attribute letter [String] "a", "b", …
      # @!attribute label [String] what the button says, the marker stripped
      # @!attribute recommended [Boolean]
      # @!attribute answer [String] what choosing it sends
      Option = Data.define(:letter, :label, :recommended, :answer) do
        # @return [Hash] the page's `QuestionOption`
        def to_h = { letter:, label:, recommended:, answer: }
      end

      # How an agent marked a yes/no question before D3 (W30), on its own line.
      # Still read, and still what the prompt shows for a plain yes/no.
      YES_NO_MARK = "answers: yes, no"

      # {YES_NO_MARK}, read forgivingly: brackets, case and spacing vary.
      YES_NO = /answers:\s*\[?\s*yes\s*,\s*no\s*\]?/i

      # A letter's marker. At the start of a line (after a bullet or bold) it
      # may be `a)`, `(a)` or `a.`, either case; inline only the parenthesised
      # lowercase forms count, because `e.g.` and `I.` are prose.
      LETTER_LINE = /^[ \t]*(?:[-*+][ \t]+)?(?:\*\*)?(?:\(([a-z])\)|([a-z])[).])(?:\*\*)?[ \t]+/i
      LETTER_INLINE = /(?<=[\s:])(?:\*\*)?(?:\(([a-z])\)|([a-z])\))(?:\*\*)?[ \t]+/

      # A number's marker, line start only: `1.`, `1)`, `Option 1:`.
      NUMBER_LINE = /^[ \t]*(?:[-*+][ \t]+)?(?:\*\*)?(?:option[ \t]+(\d{1,2})[:.)]|(\d{1,2})[.)])(?:\*\*)?[ \t]+/i

      # A numbered list is also how agents report steps already done, so one
      # counts as a choice only after something that asks.
      ASKS = /\?|\b(?:choose|chose|pick|prefer|option|which|decide)\b/i

      # The recommendation, in the ways it gets written: bracketed anywhere
      # (`(Recommended)`, `[recommended]`), or bare as the option's first or
      # last word ("Recommended. Rebase first"). A bare "recommended" mid-label
      # is prose ("the recommended layout") and stays where it is.
      RECOMMENDED = /
        [[:blank:]]*(?:\*\*|_)?[(\[][[:blank:]]*recommended[[:blank:]]*[)\]](?:\*\*|_)?[[:blank:]]*[.:,;]?
        | \A(?:\*\*|_)?recommended(?:\*\*|_)?[[:blank:]]*[.:,;—–-][[:blank:]]*
        | [[:blank:]]*[—–-][[:blank:]]*(?:\*\*|_)?recommended(?:\*\*|_)?\.?\z
      /ix

      # The option the page's text box already is. D3 makes it the last
      # choice of every question, so an agent that writes it out gets no
      # second, dead button.
      SOMETHING_ELSE = /\A(?:type|write|say)\s+something\s+(?:else\s+)?instead\b|\Asomething\s+else\b|\Aother\b/i

      # A label that runs into a new paragraph is not a label: the list ended
      # and prose followed it, so the options are not the end of the text.
      PARAGRAPH = /\n[ \t]*\n/

      class << self
        # @param text [String, nil] a question's body, Markdown
        # @return [OpenLanes::Plans::Choices, nil] nil when the text offers
        #   fewer than two options, or its options are not where it ends
        def parse(text)
          text = text.to_s.strip
          return nil if text.empty?

          marked(text) || lettered(text) || numbered(text)
        end

        # A yes/no question about +context+.
        #
        # @param context [String]
        # @return [OpenLanes::Plans::Choices]
        def yes_no(context)
          new(context: context.to_s.strip,
            options: [Option.new(letter: "a", label: "yes", recommended: false, answer: "yes"),
                      Option.new(letter: "b", label: "no", recommended: false, answer: "no")])
        end

        private

        # The W30 mark, on a line of its own.
        def marked(text)
          line = /^[ \t]*#{YES_NO.source}[ \t]*$\n?/i
          return nil unless text.match?(line)

          yes_no(text.gsub(line, ""))
        end

        # A line's marker also matches inline from its letter on, so the
        # inline match inside one (the `a)` of `- a)`) is dropped: kept, it
        # would leave the bullet behind at the end of the context.
        def lettered(text)
          lines = scan(text, LETTER_LINE) { |m| (m[1] || m[2]).downcase.ord - "a".ord }
          inline = scan(text, LETTER_INLINE) { |m| (m[1] || m[2]).ord - "a".ord }
                   .reject { |start, _, _| lines.any? { |from, to, _| (from...to).cover?(start) } }
          run(text, (lines + inline).sort_by(&:first))
        end

        def numbered(text)
          markers = scan(text, NUMBER_LINE) { |m| (m[1] || m[2]).to_i - 1 }
          choices = run(text, markers)
          choices if choices&.context&.match?(ASKS)
        end

        # Every marker in +text+ as `[start, finish, index]`, index 0 for `a`
        # or `1`.
        def scan(text, pattern)
          found = []
          text.scan(pattern) do
            match = Regexp.last_match
            found << [match.begin(0), match.end(0), yield(match)]
          end
          found
        end

        # The last run of markers that counts 0, 1, 2… up to the end of the
        # text. The last, because a context may itself mention "a) or b)"
        # before the real options; and to the end, because a list followed by
        # more prose was something other than a choice.
        def run(text, markers)
          markers.each_index.reverse_each do |first|
            next unless markers[first].last.zero?

            picked = sequence(markers.drop(first))
            next if picked.size < 2

            choices = build(text, picked)
            return choices if choices
          end
          nil
        end

        # From a marker for index 0, the next marker for 1, then 2, skipping
        # anything out of order (an `(e)` quoted inside a label).
        def sequence(markers)
          markers.each_with_object([]) do |marker, picked|
            picked << marker if marker.last == picked.size
          end
        end

        def build(text, picked)
          labels = picked.each_with_index.map do |(_, finish, _), i|
            text[finish...(picked[i + 1]&.first || text.size)].strip
          end
          return nil if labels.any? { it.empty? || it.match?(PARAGRAPH) }

          options = labels.each_with_index.map { |label, i| option(label, i) }
          options.pop if options.last&.label&.match?(SOMETHING_ELSE)
          return nil if options.size < 2

          new(context: text[0...picked.first.first].strip, options: only_one_recommended(options))
        end

        def option(raw, index)
          recommended = raw.match?(RECOMMENDED)
          label = unbold(raw.sub(RECOMMENDED, " ").strip).strip
          letter = ("a".ord + index).chr
          Option.new(letter:, label:, recommended:, answer: "#{letter}) #{label}")
        end

        # A bold marker leaves its partner behind: `**a) Rebase**` becomes
        # `Rebase**`. An odd count of `**` means one of them lost its pair.
        def unbold(label)
          label = label.sub('**', "") if label.scan("**").size.odd?
          label = label[2...-2].strip if label.start_with?("**") && label.end_with?("**") && label.size > 4
          label
        end

        # D3 says exactly one; an agent that recommends two has recommended
        # the first, and the page shows one tag rather than several.
        def only_one_recommended(options)
          first = options.index(&:recommended)
          options.each_with_index.map { |o, i| o.recommended && i != first ? o.with(recommended: false) : o }
        end
      end

      # @return [OpenLanes::Plans::Choices::Option, nil]
      def recommended = options.find(&:recommended)

      # @return [Boolean] whether the options are yes and no
      def yes_no? = options.map(&:label) == %w[yes no]

      # @return [Array<Hash>] the page's `QuestionOption[]`
      def to_a = options.map(&:to_h)
    end
  end
end

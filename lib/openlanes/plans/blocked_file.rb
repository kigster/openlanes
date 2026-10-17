# frozen_string_literal: true

module OpenLanes
  module Plans
    # The bodies of the questions in `blocked.md`: the lines under each
    # `## Bn` heading, up to the next heading of any kind or the next `## An`;
    # and, the same way, the bodies of the answers under `## An`.
    #
    # The page reads a body to show it and the engine reads one to rewrite it
    # into choices, so both find its edges here; two readers with two ideas
    # of where a question ends would rewrite text the page never showed.
    # Pure: text in, text out.
    module BlockedFile
      # Any Markdown heading, which ends the body of the question above it.
      HEADING = /^[ \t]{0,3}\#{1,6}[ \t]/

      module_function

      # @param text [String] the whole of blocked.md
      # @return [Hash{Integer => String}] each question's number to the
      #   lines under its heading; a number written twice keeps the last
      def bodies(text)
        lines = text.to_s.lines
        spans(lines).transform_values { |(from, to)| lines[from...to].join }
      end

      # The answers waiting under `## An` headings, by number, which is how
      # the harness copies each question and its answer into the asking
      # agent's journal (M3) before the broker drains them.
      #
      # @param text [String] the whole of blocked.md
      # @return [Hash{Integer => String}] each answer's number to the lines
      #   under its heading
      def answers(text)
        lines = text.to_s.lines
        spans(lines, ANSWER_BLOCK).transform_values { |(from, to)| lines[from...to].join }
      end

      # +text+ with question +number+'s body replaced by +body+, its heading
      # and everything else as they were.
      #
      # @param text [String] the whole of blocked.md
      # @param number [Integer]
      # @param body [String]
      # @return [String, nil] nil when the file has no such question
      def replace(text, number, body)
        lines = text.to_s.lines
        from, to = spans(lines)[number]
        return nil unless from

        lines[from - 1] = "#{lines[from - 1].chomp}\n"
        section = ["\n", "#{body.strip}\n"]
        section << "\n" if to < lines.size
        (lines[0...from] + section + lines[to..]).join
      end

      # @param lines [Array<String>]
      # @param pattern [Regexp] {OPEN_BLOCK} for questions, {ANSWER_BLOCK}
      #   for answers; either kind of heading ends the other's body
      # @return [Hash{Integer => Array(Integer, Integer)}] each block's
      #   number to the first line under its heading and the line that ends it
      def spans(lines, pattern = OPEN_BLOCK)
        found = {}
        open = nil
        lines.each_with_index do |line, i|
          number = line[pattern, 1]
          if number || line.match?(HEADING) || line.match?(OPEN_BLOCK) || line.match?(ANSWER_BLOCK)
            found[open.first] = [open.last, i] if open
            open = number && [number.to_i, i + 1]
          end
        end
        found[open.first] = [open.last, lines.size] if open
        found
      end
    end
  end
end

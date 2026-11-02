# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # Keeps a declared ordering alive when the plan in the middle leaves (X9).
    #
    # `A -> B -> C` means A waits for B and B waits for C. Removing B without
    # this would let A start before C, which nobody ever said was fine, so A
    # takes over B's dependencies. Everything is computed from one reading of
    # the graph before anything is written, which is what makes removing
    # several plans at once come out the same in any order.
    class Rewiring
      # One dependent's `depends_on:`, before and after.
      #
      # @!attribute [r] ordinal
      #   @return [String] the dependent
      # @!attribute [r] path
      #   @return [String] its spec.md, absolute
      # @!attribute [r] before
      #   @return [Array<String>]
      # @!attribute [r] after
      #   @return [Array<String>]
      # @!attribute [r] problem
      #   @return [String, nil] why this dependent cannot be rewritten
      Edit = Data.define(:ordinal, :path, :before, :after, :problem) do
        # @return [String] e.g. `001.00: 002.00 → 003.00, 004.00`
        def to_s
          return "#{ordinal}: #{problem}" if problem

          gone = before - after
          "#{ordinal}: #{gone.join(", ")} → #{(after - before).then { it.empty? ? "(nothing)" : it.join(", ") }}"
        end
      end

      # One reading of the graph, so every edit is computed from the same one.
      Reading = Data.define(:removed, :graph, :states, :leave) do
        # @return [Boolean] whether this ordinal is finished, or out of the list
        def met?(ordinal) = Plans::Dependencies::MET.include?(states[ordinal])
      end

      # @param tree [OpenLanes::Plans::Tree]
      def initialize(tree:)
        @tree = tree.everything
      end

      # @param removed [Array<String>] canonical ordinals leaving the active list
      # @return [Array<Edit>] one per dependent; nothing is written
      def plan(removed, leave: [])
        subjects = @tree.reload.subjects
        reading = Reading.new(removed:,
          leave:,
          graph:  subjects.to_h { [it.feature.ordinal.to_s, Plans::Spec.for(it).depends_on] },
          states: subjects.to_h { [it.feature.ordinal.to_s, it.status.key] })
        subjects.filter_map { edit_for(it, reading) }
      end

      # @param edits [Array<Edit>]
      # @return [Array<Edit>] +edits+, for the caller to report
      def apply(edits)
        edits.each do |edit|
          next UI.log("depends_on not rewritten: #{edit}", level: :warn) if edit.problem

          File.write(edit.path, Plans::Spec.with_depends_on(File.read(edit.path), edit.after))
          OpenLanes.stage(edit.path, edit.path)
          UI.log("depends_on rewritten: #{edit}")
        end
        edits
      end

      # Notes the rewrites a removal caused in the file that explains it, which
      # is what a person restoring the plan needs (X9).
      #
      # @param edits [Array<Edit>]
      # @param ordinal [String] the plan that left
      # @param path [String] its reason file
      # @return [void]
      def record(edits, ordinal, path)
        mine = edits.select { !it.problem && it.before.include?(ordinal) }
        return if mine.empty? || !File.file?(path)

        File.write(path, "#{File.read(path).rstrip}\n\n## Dependents rewired\n\n#{mine.map { "- #{it}" }.join("\n")}\n")
      end

      private

      # @return [Edit, nil]
      def edit_for(subject, reading)
        ordinal = subject.feature.ordinal.to_s
        return nil if reading.removed.include?(ordinal) || reading.met?(ordinal)

        path = File.join(subject.feature.path, Plans::Spec::FILENAME)
        before = reading.graph[ordinal]
        return unreadable(subject, ordinal, path, reading.removed) if before.nil?
        return nil unless before.intersect?(reading.removed)

        after = rewired(ordinal, before, reading)
        Edit.new(ordinal:, path:, before:, after:, problem: problem_with(ordinal, path, after, reading))
      end

      # @return [String, nil] why this dependent keeps what it has
      def problem_with(ordinal, path, after, reading)
        return "someone is working in it, so depends_on was left as written" if reading.leave.include?(ordinal)

        "depends_on could not be rewritten safely, so it was left as written" unless faithful?(path, after)
      end

      # The rewrite is a text edit on the author's YAML, so it is checked by
      # reading the result back: only that one key may differ, or the spec
      # would lose its other keys and the gate its edges without a word.
      #
      # @return [Boolean]
      def faithful?(path, after)
        text = File.read(path)
        was, was_body = Frontmatter.split(text)
        now, now_body = Frontmatter.split(Plans::Spec.with_depends_on(text, after))
        key = Plans::Spec::DEPENDS_ON_KEY
        now_body == was_body && now.except(key) == was.except(key) &&
          Array(now[key]).map(&:to_s) == (after.empty? ? [Plans::Spec::NO_DEPENDENCIES] : after)
      rescue Psych::Exception
        false
      end

      # A spec whose frontmatter does not parse yields no list, but its text
      # may still name a removed plan. Guessing at a broken file is how it
      # gets worse, so it is reported and left for a person.
      #
      # @return [Edit, nil]
      def unreadable(subject, ordinal, path, removed)
        problems = Plans::Spec.for(subject).problems.grep(/not valid YAML/)
        text = subject.read(Plans::Spec::FILENAME).to_s
        return nil if problems.empty? || removed.none? { text.match?(/\b#{it[/\A\d+/]}\b/) }

        Edit.new(ordinal:, path:, before: [], after: [], problem: "spec.md did not parse, so depends_on was left as written")
      end

      # @return [Array<String>] sorted, without duplicates or +ordinal+ itself
      def rewired(ordinal, before, reading)
        kept, gone = before.partition { !reading.removed.include?(it) }
        inherited = gone.flat_map { expand(it, reading, []) }.reject { reading.met?(it) }
        (kept + inherited).uniq.reject { it == ordinal }.sort
      end

      # @return [Array<String>] what +entry+ stands for once the removed are gone
      def expand(entry, reading, seen)
        return [entry] unless reading.removed.include?(entry)
        return [] if seen.include?(entry)

        Array(reading.graph[entry]).flat_map { expand(it, reading, seen + [entry]) }
      end
    end
  end
end

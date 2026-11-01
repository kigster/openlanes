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
      Reading = Data.define(:removed, :graph, :states) do
        # @return [Boolean] whether this ordinal is finished, or out of the list
        def met?(ordinal) = Plans::Dependencies::MET.include?(states[ordinal])
      end

      # @param tree [OpenLanes::Plans::Tree]
      def initialize(tree:)
        @tree = tree.everything
      end

      # @param removed [Array<String>] canonical ordinals leaving the active list
      # @return [Array<Edit>] one per dependent; nothing is written
      def plan(removed)
        subjects = @tree.reload.subjects
        reading = Reading.new(removed:,
          graph:  subjects.to_h { [it.feature.ordinal.to_s, Plans::Spec.for(it).depends_on] },
          states: subjects.to_h { [it.feature.ordinal.to_s, it.status.key] })
        subjects.filter_map { edit_for(it, reading) }
      end

      # @param edits [Array<Edit>]
      # @return [Array<Edit>] +edits+, for the caller to report
      def apply(edits)
        edits.reject(&:problem).each do |edit|
          File.write(edit.path, Plans::Spec.with_depends_on(File.read(edit.path), edit.after))
        end
        edits
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

        Edit.new(ordinal:, path:, before:, after: rewired(ordinal, before, reading), problem: nil)
      end

      # A spec whose frontmatter does not parse yields no list, but its text
      # may still name a removed plan. Guessing at a broken file is how it
      # gets worse, so it is reported and left for a person.
      #
      # @return [Edit, nil]
      def unreadable(subject, ordinal, path, removed)
        problems = Plans::Spec.for(subject).problems.grep(/not valid YAML/)
        return nil if problems.empty? || removed.none? { subject.read(Plans::Spec::FILENAME).to_s.include?(it) }

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

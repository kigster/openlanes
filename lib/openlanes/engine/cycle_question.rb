# frozen_string_literal: true

module OpenLanes
  module Engine
    # What a person is asked when plans wait on each other. The gate holds
    # every plan on a cycle for good, and said so only in the held report,
    # where nothing prompted anyone to fix it.
    #
    # Nothing is stored: the cycle in the `depends_on:` keys is the question,
    # so it is asked for as long as the cycle is there and goes when it is
    # broken, by an answer here or by an edit to a spec. It hangs on the
    # lowest plan of the tangle, once, however many plans are in it.
    #
    # The answer removes one plan's dependencies on the others in the tangle,
    # so that plan can start. A tangle holding a second cycle asks again.
    module CycleQuestion
      # The question's name on its plan, as `Q1` is the quality question's.
      NAME = "C1"

      # @return [String]
      HEADING = "These plans wait on each other, so none of them can start"

      # The letter of the one option offered; anything else is a plan number.
      RECOMMENDED = "a"

      # An answer that names no plan in the tangle.
      class Invalid < Error; end

      # What an answer did.
      #
      # @!attribute [r] plan
      #   @return [String] the plan that may now start
      # @!attribute [r] removed
      #   @return [Array<String>] the entries taken out of its `depends_on:`
      Fix = Data.define(:plan, :removed) do
        # @return [String]
        def to_s = "#{plan} no longer depends on #{removed.join(", ")}"
      end

      module_function

      # The open question on this plan, as the page's `Question`s.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param deps [OpenLanes::Plans::Dependencies]
      # @return [Array<Hash>] empty unless this plan is the lowest of a tangle
      def questions(subject, deps)
        ordinal = subject.feature.ordinal.to_s
        tangle = deps.tangle_of(ordinal)
        return [] unless tangle&.first == ordinal

        plans_dir = File.basename(File.dirname(subject.feature.path))
        [{ id: "#{ordinal}/#{NAME}", number: 1, kind: "cycle", heading: HEADING,
           body: body(deps.cycle_of(ordinal), tangle, plans_dir), agent: nil, owner: "technical",
           options: [option(ordinal, removable(deps, ordinal, tangle))], held: false, asked_at: nil }]
      end

      # @param ordinal [String] the lowest plan of the tangle
      # @param removed [Array<String>] what its `depends_on:` would lose
      # @return [Hash] the one `QuestionOption`
      def option(ordinal, removed)
        label = "Remove #{ordinal}'s dependency on #{removed.join(", ")}, so #{ordinal} runs next"
        { letter: RECOMMENDED, label:, recommended: true, answer: "#{RECOMMENDED}) #{label}" }
      end

      # Break the cycle the way the answer says: the option's letter for the
      # lowest plan, or the number of the plan that should run next.
      #
      # @param tree [OpenLanes::Plans::Tree]
      # @param ordinal [String] the plan the question hangs on
      # @param text [String] "a) Remove …", "a", or a plan number such as "050"
      # @return [Fix, nil] nil when the question is not open on that plan
      # @raise [Invalid] on an answer that names no plan in the tangle, or a
      #   spec whose `depends_on:` cannot be rewritten safely
      def answer!(tree, ordinal, text)
        deps = tree.reload.dependencies
        tangle = deps.tangle_of(ordinal)
        return nil unless tangle&.first == ordinal

        chosen = chosen(text, tangle)
        removed = removable(deps, chosen, tangle)
        rewrite(File.join(tree.find(Plans::Ordinal.parse(chosen)).feature.path, Plans::Spec::FILENAME),
          deps.depends_on(chosen) - removed)
        tree.reload
        Fix.new(plan: chosen, removed:)
      end

      # @return [Array<String>] the entries of this plan that keep it in the tangle
      def removable(deps, ordinal, tangle) = deps.depends_on(ordinal).to_a & tangle

      # @return [String] the plan whose dependencies go
      # @raise [Invalid]
      def chosen(text, tangle)
        said = text.to_s.strip
        return tangle.first if said.match?(/\A#{RECOMMENDED}\)?(?:\s|\z)/i)

        named = Plans::Ordinal.parse(said)&.to_s
        return named if tangle.include?(named)

        raise Invalid, "#{NAME} takes #{RECOMMENDED}) or one of #{tangle.join(", ")}, not #{said[0, 40].inspect}"
      end

      # The rewrite is a text edit on the author's YAML, so it is read back
      # before it is written, as {Lifecycle::Rewiring} does: a spec that
      # would come out with other entries is left for a person.
      #
      # @param path [String] a spec.md
      # @param after [Array<String>]
      # @return [void]
      # @raise [Invalid]
      def rewrite(path, after)
        was = File.read(path)
        now = Plans::Spec.with_depends_on(was, after)
        raise Invalid, "depends_on in #{path} could not be rewritten safely; edit it by hand" unless faithful?(was, now, after)

        File.write(path, now)
        OpenLanes.stage(path, path)
      end

      # @return [Boolean] whether only `depends_on:` differs, and reads as +after+
      def faithful?(was, now, after)
        key = Plans::Spec::DEPENDS_ON_KEY
        old_meta, old_body = Frontmatter.split(was)
        new_meta, new_body = Frontmatter.split(now)
        new_body == old_body && new_meta.except(key) == old_meta.except(key) &&
          Array(new_meta[key]).map(&:to_s) == (after.empty? ? [Plans::Spec::NO_DEPENDENCIES] : after)
      rescue Psych::Exception
        false
      end

      # @param cycle [Array<String>] a shortest cycle, from the lowest plan back to it
      # @param tangle [Array<String>]
      # @param plans_dir [String] the plans directory's name, as a person finds it
      # @return [String] Markdown
      def body(cycle, tangle, plans_dir)
        <<~MARKDOWN.strip
          `#{cycle.join(" → ")}`: each plan's `depends_on:` names the next, so no order lets any of them start.

          The plans in the loop are #{tangle.join(", ")}. Their specs are in `#{plans_dir}/`; read them to see which should be built first.

          Choose the option below, or type the number of the plan that should run next. Either way that plan's dependencies on the others in the loop are removed from its `spec.md`, and nothing else changes.
        MARKDOWN
      end
    end
  end
end

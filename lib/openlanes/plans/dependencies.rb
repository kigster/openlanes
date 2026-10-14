# frozen_string_literal: true

module OpenLanes
  module Plans
    # Who waits for whom, read from every plan's `depends_on:` and nothing
    # else. Only the forward edge is written down; `blocks` is derived here
    # every time and never stored, so dropping a dependency cannot leave a
    # stale reverse entry behind in the plan it used to name (N6).
    #
    # Every answer is an array of canonical `NNN.MM` strings, sorted. Asking
    # about a plan the tree does not hold answers empty rather than raising.
    class Dependencies
      # The states in which a dependency is done. Everything else, blocked and
      # deferred included, keeps the dependent waiting.
      DONE = %i[approved deployed].freeze

      # @param tree [OpenLanes::Plans::Tree]
      def initialize(tree)
        @tree = tree
      end

      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [Array<String>, nil] the declared list, nil when the key is absent
      def depends_on(ordinal) = declared[key(ordinal)]

      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [Array<String>] every plan whose `depends_on` names this one
      def blocks_of(ordinal) = reverse.fetch(key(ordinal), [])

      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [Array<String>] declared entries that are not done, unknown ones included
      def waiting_on(ordinal) = edges(ordinal).reject { done?(it) }

      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [Array<String>] declared entries with no folder in the tree
      def unknown(ordinal) = edges(ordinal).reject { states.key?(it) }

      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [Array<String>] declared entries naming a done plan, which the gate ignores
      def closed(ordinal) = edges(ordinal).select { done?(it) }

      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [Array<String>, nil] the cycle through this plan, starting and
      #   ending with it, or nil when it is on none
      def cycle_of(ordinal)
        wanted = key(ordinal)
        found = cycles.find { it.include?(wanted) } or return nil

        ring = found[0...-1]
        ring = ring.rotate(ring.index(wanted))
        ring + [wanted]
      end

      # Every cycle once, each starting and ending at its lowest ordinal.
      #
      # @return [Array<Array<String>>]
      def cycles = @cycles ||= find_cycles

      # Why the engine must not start this plan, or nil when it may. A cycle
      # outranks a plain wait, since waiting on a cycle never ends.
      #
      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [String, nil] e.g. "waiting on 034.00" or "cycle: 034.00 → 050.00 → 034.00"
      def reason(ordinal)
        cycle = cycle_of(ordinal)
        return "cycle: #{cycle.join(" → ")}" if cycle

        open = waiting_on(ordinal)
        "waiting on #{open.join(", ")}" unless open.empty?
      end

      private

      # @return [String]
      def key(ordinal) = (ordinal.is_a?(Ordinal) ? ordinal : Ordinal.parse(ordinal)).to_s

      # @return [Array<String>]
      def edges(ordinal) = depends_on(ordinal) || []

      # @return [Boolean]
      def done?(ordinal) = DONE.include?(states[ordinal])

      # @return [Hash{String => Symbol}] ordinal => status key
      def states = @states ||= @tree.subjects.to_h { [it.feature.ordinal.to_s, it.status.key] }

      # @return [Hash{String => Array<String>, nil}]
      def declared
        @declared ||= @tree.subjects.to_h { [it.feature.ordinal.to_s, Spec.for(it).depends_on] }
      end

      # @return [Hash{String => Array<String>}]
      def reverse
        @reverse ||= declared.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(from, tos), out|
          Array(tos).each { out[it] << from }
        end.transform_values(&:sort)
      end

      # Depth-first search over the declared edges. A cycle is recorded when
      # the walk meets a plan already on its own path, rotated to its lowest
      # ordinal so the same ring found from two starts is kept once.
      #
      # @return [Array<Array<String>>]
      def find_cycles
        found = []
        visit = lambda do |node, path|
          edges(node).each do |nxt|
            if (at = path.index(nxt))
              ring = path[at..]
              ring = ring.rotate(ring.index(ring.min))
              found << (ring + [ring.first])
            elsif declared.key?(nxt)
              visit.call(nxt, path + [nxt])
            end
          end
        end
        declared.keys.sort.each { visit.call(it, [it]) }
        found.uniq.sort
      end
    end
  end
end

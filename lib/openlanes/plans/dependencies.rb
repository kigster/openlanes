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
    #
    # Plans joined by an unfinished edge, in either direction, form a group,
    # and a group works on one plan at a time (#95): the first in topological
    # order that may start, so two plans that will meet in a common dependent
    # are never built against each other's moving code. Separate groups run
    # side by side. An edge to a finished plan joins nothing, so the
    # dependents of a shipped plan part ways.
    class Dependencies
      # The states in which a dependency is done. Everything else, blocked and
      # deferred included, keeps the dependent waiting.
      DONE = %i[approved deployed].freeze

      # The states before the build. Work in them is documents only, so a plan
      # here gives up its group's turn to one whose code is already under way.
      BEFORE_BUILD = %i[retroactive new researched ready_for_linking ready_for_planning planned].freeze

      # @param tree [OpenLanes::Plans::Tree]
      # @param status_of [#call, nil] the state to judge a plan by, when it is
      #   not the folder's name. A dry run renames nothing, so without this a
      #   prerequisite whose contents already say ✅ would still hold its
      #   dependents back, while a real run would have reconciled it and let
      #   them start.
      def initialize(tree, status_of: nil)
        @tree = tree
        @status_of = status_of || :status.to_proc
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
      # @return [Array<String>, nil] a shortest cycle through this plan,
      #   starting and ending with it, or nil when it is on none
      def cycle_of(ordinal)
        wanted = key(ordinal)
        return nil unless looped?(wanted)

        (@rings ||= {})[wanted] ||= ring_from(wanted)
      end

      # One shortest cycle per tangle of plans that wait on each other, each
      # starting and ending at the tangle's lowest ordinal. A tangle can hold
      # more cycles than this; {#cycle_of} names one through any plan in it.
      #
      # @return [Array<Array<String>>]
      def cycles = @cycles ||= components.select { looped?(it.first) }.map { cycle_of(it.first) }.sort

      # Unfinished plans joined by an unfinished edge, in either direction.
      #
      # @return [Array<Array<String>>] each group sorted, groups by first ordinal
      def groups
        @groups ||= begin
          # Union-find, walked in a loop rather than recursively, so a long
          # chain of plans cannot raise SystemStackError inside a tick.
          root = unfinished.to_h { [it, it] }
          find = lambda do |x|
            x = root[x] = root[root[x]] until root[x] == x
            x
          end
          unfinished.each do |from|
            open_edges.fetch(from).each { |to| root[find.call(from)] = find.call(to) if root.key?(to) }
          end
          unfinished.group_by { find.call(it) }.values.map(&:sort).sort
        end
      end

      # Each group in topological order, prerequisites first, ties by
      # ordinal. Plans on a cycle cannot be ordered and come last.
      #
      # @return [Array<Array<String>>] parallel to {#groups}
      def order = @order ||= groups.map { sorted(it) }

      # The plan whose turn it is in this plan's group, or nil when no plan
      # in it may start: the first in {#order} that may, preferring one whose
      # build is already under way, so work already done is never stranded.
      #
      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [String, nil]
      def head(ordinal)
        wanted = key(ordinal)
        line = order.find { it.include?(wanted) } or return nil
        (@heads ||= {}).fetch(line.first) do
          ready = line.select { startable?(it) }
          @heads[line.first] = ready.find { !BEFORE_BUILD.include?(states[it]) } || ready.first
        end
      end

      # Why the engine must not start this plan, or nil when it may. A cycle
      # outranks a plain wait, since waiting on a cycle never ends. An entry
      # naming no plan is said apart from a real wait: a typo such as
      # "099.00" holds the plan forever, and "waiting on 099.00" in the held
      # report read like a wait that would end on its own. A plan free of
      # all three still waits while another plan holds its group's turn.
      #
      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [String, nil] e.g. "waiting on 034.00", "unknown plan 099.00",
      #   "cycle: 034.00 → 050.00 → 034.00" or "queued behind 034.00"
      def reason(ordinal)
        own = own_reason(ordinal) and return own

        first = head(ordinal)
        "queued behind #{first}" if first && first != key(ordinal)
      end

      private

      # {#reason} without the group's turn: what this plan's own edges say.
      #
      # @param ordinal [OpenLanes::Plans::Ordinal, String]
      # @return [String, nil]
      def own_reason(ordinal)
        cycle = cycle_of(ordinal)
        return "cycle: #{cycle.join(" → ")}" if cycle

        missing = unknown(ordinal)
        open = waiting_on(ordinal) - missing
        parts = []
        parts << "unknown plan #{missing.join(", ")}" unless missing.empty?
        parts << "waiting on #{open.join(", ")}" unless open.empty?
        parts.join("; ") unless parts.empty?
      end

      # @return [Boolean] whether this plan could take its group's turn:
      #   neither parked nor done, and free of its own reasons to wait
      def startable?(ordinal) = !StateMachine::SETTLED.include?(states[ordinal]) && own_reason(ordinal).nil?

      # @return [Array<String>] plans in the tree that are not done
      def unfinished = @unfinished ||= declared.keys.reject { done?(it) }.sort

      # Kahn's algorithm over the group's open edges, taking the lowest
      # ordinal whenever several plans are free. The free list stays sorted
      # by binary insertion, so a group of thousands sorts in a blink.
      #
      # @param group [Array<String>]
      # @return [Array<String>]
      def sorted(group)
        members = group.to_set
        pending = group.to_h { |plan| [plan, open_edges.fetch(plan).count { members.include?(it) }] }
        free = pending.select { |_, n| n.zero? }.keys.sort
        out = []
        until free.empty?
          plan = free.shift
          out << plan
          pending.delete(plan)
          blocks_of(plan).each do |waiter|
            next unless pending.key?(waiter) && (pending[waiter] -= 1).zero?

            free.insert(free.bsearch_index { it >= waiter } || free.size, waiter)
          end
        end
        out + pending.keys.sort
      end

      # @return [String]
      def key(ordinal) = (ordinal.is_a?(Ordinal) ? ordinal : Ordinal.parse(ordinal)).to_s

      # @return [Array<String>]
      def edges(ordinal) = depends_on(ordinal) || []

      # @return [Boolean]
      def done?(ordinal) = DONE.include?(states[ordinal])

      # @return [Hash{String => Symbol}] ordinal => status key
      def states = @states ||= @tree.subjects.to_h { [it.feature.ordinal.to_s, @status_of.call(it).key] }

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

      # The edges that can still hold anything up: entries not yet done that
      # name a plan in the tree. A dependency on a ✅ plan is already met, so
      # it closes no cycle; two plans that once named each other stop being
      # deadlocked the moment one of them ships.
      #
      # @return [Hash{String => Array<String>}]
      def open_edges = @open_edges ||= declared.keys.to_h { [it, waiting_on(it).select { declared.key?(it) }] }

      # @return [Boolean] whether this plan sits on a cycle of open edges
      def looped?(ordinal)
        group = group_of[ordinal] or return false
        group.size > 1 || open_edges.fetch(ordinal).include?(ordinal)
      end

      # @return [Hash{String => Array<String>}] ordinal => its strongly connected component
      def group_of = @group_of ||= components.each_with_object({}) { |g, out| g.each { out[it] = g } }

      # Tarjan's strongly connected components over {#open_edges}, so each
      # plan is visited once. Enumerating every path instead revisited shared
      # subgraphs on each one: 28 plans each waiting on the two before took
      # 2.6 seconds and two million visits, and the dispatcher asks on every
      # tick. The walk keeps its own stack of frames rather than recursing,
      # so a chain of a few thousand plans cannot raise SystemStackError
      # inside a dispatcher tick.
      #
      # @return [Array<Array<String>>] each component sorted
      def components
        @components ||= begin
          index = {}
          low = {}
          stack = []
          on_stack = {}
          out = []
          open_edges.keys.sort.each do |root|
            next if index.key?(root)

            frames = [[root, 0]]
            index[root] = low[root] = index.size
            stack << root
            on_stack[root] = true
            until frames.empty?
              v, i = frames.last
              w = open_edges.fetch(v)[i]
              if w
                frames.last[1] += 1
                if !index.key?(w)
                  index[w] = low[w] = index.size
                  stack << w
                  on_stack[w] = true
                  frames << [w, 0]
                elsif on_stack[w]
                  low[v] = [low[v], index[w]].min
                end
                next
              end

              frames.pop
              parent = frames.last&.first
              low[parent] = [low[parent], low[v]].min if parent
              next unless low[v] == index[v]

              group = []
              group << stack.pop.tap { on_stack.delete(it) } until group.last == v
              out << group.sort
            end
          end
          out
        end
      end

      # Breadth-first from +start+ back to itself inside its component, so
      # the cycle named is a shortest one and the walk is linear.
      #
      # @param start [String]
      # @return [Array<String>]
      def ring_from(start)
        group = group_of.fetch(start)
        parent = { start => nil }
        queue = [start]
        until queue.empty?
          node = queue.shift
          open_edges.fetch(node).sort.each do |nxt|
            next unless group.include?(nxt)

            if nxt == start
              path = [node]
              path.unshift(parent[path.first]) while parent[path.first]
              return path + [start]
            end
            next if parent.key?(nxt)

            parent[nxt] = node
            queue << nxt
          end
        end
      end
    end
  end
end

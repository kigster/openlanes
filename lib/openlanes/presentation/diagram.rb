# frozen_string_literal: true

module OpenLanes
  module Presentation
    # `openlanes states` — the state machine as a terminal picture.
    #
    # {Documentation} already renders this machine as a Markdown table and a
    # mermaid block, for a browser. This is the same machine, walked the same
    # way, shaped for a terminal instead: unicode arrows, no browser required.
    #
    # Every section below is read off {StateMachine} and {STATUSES} rather than
    # drawn by hand, for the reason {Documentation} gives for doing the same
    # thing: three hand-maintained pictures of this machine have already
    # drifted apart once, and a fourth is not the fix.
    class Diagram
      include UI

      # Drawn between two states on the same line.
      ARROW = "──▶"

      # @return [String] the whole diagram, newline-terminated
      def render
        [
          heading,
          spine_section,
          rejoin_section,
          other_section,
          terminal_section,
          family_section
        ].compact.join("\n\n") + "\n"
      end

      private

      # @return [String]
      def heading
        paint("Spec → Plan → Build — the state machine", :bold) + "\n" +
          paint("(derived from lib/openlanes/state_machine.rb — `openlanes docs` for the Markdown form)",
            :bright_black)
      end

      # The path a bare `promote!` walks: {StateMachine::SPINE}, followed from
      # `:new` until a state has no entry left to follow.
      #
      # @return [String]
      def spine_section
        section("MAIN SPINE",
          "a bare `promote` walks this path",
          ["  " + spine_chain.map { |key| node(key) }.join(" #{ARROW} ")])
      end

      # {StateMachine::SPINE} entries whose source never appears on the walk
      # above — states that sit off the spine but whose default `promote!`
      # rejoins it, e.g. a rejected pull request resubmitted for review.
      #
      # @return [String, nil]
      def rejoin_section
        rows = Plans::StateMachine::SPINE
               .except(*spine_chain)
               .map { |from, to| "  #{node(from)} #{ARROW} #{node(to)}" }

        section("REJOINING THE SPINE", "off-spine states whose default promotion lands back on it", rows)
      end

      # Everything {StateMachine} allows that the two sections above do not
      # already draw: blocking, deferring, discarding, review outcomes,
      # rollback — read off {StateMachine.outbound} state by state, in
      # {STATUSES} order, so nothing the machine permits is left undrawn.
      #
      # @return [String, nil]
      def other_section
        drawn = Plans::StateMachine::SPINE.to_a

        groups = Plans::STATUSES.filter_map { |s|
          targets = Plans::StateMachine.outbound(s.key).reject { |to| drawn.include?([s.key, to]) }
          [s.key, targets] unless targets.empty?
        }

        section("OTHER TRANSITIONS",
          "everything else the machine permits",
          groups.flat_map { |key, targets|
            fan_out(key, targets)
          })
      end

      # @return [String, nil]
      def terminal_section
        rows = Plans::STATUSES.select(&:terminal?).map { |s| "  #{node(s.key)}" }
        section("TERMINAL", "nothing follows these", rows)
      end

      # {StateMachine::FAMILIES} share an invariant on purpose, and a folder's
      # contents alone cannot tell their members apart — worth saying next to a
      # diagram, or the members read like an oversight rather than a rule.
      #
      # @return [String, nil]
      def family_section
        rows = Plans::StateMachine::FAMILIES.map { |members| "  #{members.map { |key| node(key) }.join(" / ")}" }

        section("LOOK-ALIKE FAMILIES", "same contents on disk; only the folder name tells them apart", rows)
      end

      # `:new`, followed through {StateMachine::SPINE} until nothing follows.
      #
      # @return [Array<Symbol>]
      def spine_chain
        @spine_chain ||= [].tap { |chain|
          key = :new
          while key
            chain << key
            key = Plans::StateMachine::SPINE[key]
          end
        }
      end

      # One state and its outbound arrows, drawn as a small tree so several
      # targets from one source read as a fan-out rather than as unrelated
      # lines that happen to repeat the source.
      #
      # @param key [Symbol]
      # @param targets [Array<Symbol>]
      # @return [Array<String>]
      def fan_out(key, targets)
        lines = targets.each_with_index.map { |to, i|
          connector = i == targets.size - 1 ? "└─▶" : "├─▶"
          "      #{connector} #{node(to)}"
        }
        ["  #{node(key)}", *lines]
      end

      # @param key [Symbol]
      # @return [String]
      def node(key)
        status = Plans::STATUS_BY_KEY.fetch(key)
        paint("#{status.emoji} #{status.label}", :bold)
      end

      # @param title [String]
      # @param subtitle [String]
      # @param rows [Array<String>]
      # @return [String, nil] nil when there is nothing to show, so {#render} can drop it
      def section(title, subtitle, rows)
        return nil if rows.empty?

        "#{paint(title, :bold)}  #{paint("(#{subtitle})", :bright_black)}\n\n#{rows.join("\n")}"
      end
    end
  end
end

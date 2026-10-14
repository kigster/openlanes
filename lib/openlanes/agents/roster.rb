# frozen_string_literal: true

module OpenLanes
  module Agents
    # `openlanes agents` — who the specialists are and what each is offered
    # work from. Reading one in full is {Viewer}'s job: the definition file is
    # already the whole truth, so `agents describe` opens it rather than
    # restating it.
    #
    # {#list} returns a string and prints nothing, the same bargain {Reporter}
    # makes, so the caller decides where the text goes and the table stays
    # pipeable.
    #
    # Everything here is read from the definition files. Nothing about a
    # specialty is restated in Ruby, because a second copy of "who does what" is
    # a copy that drifts from the frontmatter the loop actually routes on.
    class Roster
      # Columns, so the header and the rows cannot drift apart.
      HEADINGS = ["Agent", "Handles", "Advances to", "Runs on", "Lanes"].freeze

      # What an agent with no `advances_to` is, in the one word that explains why
      # `run` never offers it work.
      READ_ONLY = "read-only"

      # What an agent that handles only {StateMachine::SETTLED} states advances
      # to. `run` never starts it; a command does, and `resync` then names the
      # folder by what its files justify.
      BY_CONTENTS = "by contents"

      # @param agents [OpenLanes::Agents::Registry]
      def initialize(agents: Registry.new)
        @agents = agents
      end

      # @return [OpenLanes::Agents::Registry]
      attr_reader :agents

      # One row per agent, in name order, framed by {UI.table}.
      #
      # @return [String] newline-terminated
      def list
        all = agents.all
        return "No agent definitions in #{agents.dir}\n" if all.empty?

        UI.table(all.map { |agent| row(agent) }, header: HEADINGS)
      end

      private

      # A state as its words alone, deliberately without the emoji that every
      # other rendering of a state carries. The table widget pads a cell to a
      # width it measures in characters, while the terminal draws a status emoji
      # in two cells; the variation-selector ones (⭕ 🛑 ⚪ ⭐ ⏪) are two
      # characters drawn in two cells, so no single count is right for all of
      # them. A row carrying one lands short or long and the frame stops lining
      # up. The label says the same thing unambiguously, and is worth more than
      # the emoji is. {Reporter} lays its own columns out with {UI.fit} and so
      # keeps the emoji.
      #
      # @param key [Symbol]
      # @return [String]
      def state(key)
        status = Plans::STATUS_BY_KEY[key] or return key.to_s
        status.label
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @return [String]
      def handles(agent) = agent.handles.map { |key| state(key) }.join(", ")

      # @param agent [OpenLanes::Agents::Agent]
      # @return [String]
      def advances(agent)
        return state(agent.advances_to) if agent.advances_to
        return BY_CONTENTS if agent.handles.any? && agent.handles.all? { |key| Plans::StateMachine::SETTLED.include?(key) }

        READ_ONLY
      end

      # The widget measures and pads the cells, so they arrive painted only.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @return [Array<String>] one cell per entry in {HEADINGS}
      def row(agent)
        [UI.paint(agent.name, :bright_cyan),
         handles(agent),
         UI.paint(advances(agent), agent.read_only? ? :bright_black : :green),
         UI.paint(runs_on(agent), :bright_black),
         UI.paint(agent.lanes.empty? ? "all" : agent.lanes.join(", "), :bright_black)]
      end

      # The agent's own settings, before any spec.md overrides them: the
      # model, the effort, and the adapter when it is not the default.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @return [String] e.g. `opus/high`, `codex:gpt-5-codex/medium`
      def runs_on(agent)
        model = Agents::Profile.resolve(agent).label
        agent.effort ? "#{model}/#{agent.effort}" : model
      end
    end
  end
end

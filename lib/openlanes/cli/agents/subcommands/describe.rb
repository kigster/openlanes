# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes agents …` — the specialist roster.
    module Agents
      # `openlanes agents describe [NAME]`
      class Describe < Dry::CLI::Command
        include UI

        desc "Open one specialist's definition in a Markdown viewer"

        argument :name,
          required: false,
          desc:     "Which specialist, full name or a fragment, e.g. #{OpenLanes::Agents::Names::RESEARCHER} (default: every one)"

        option :mdfried,
          type:    :boolean,
          default: false,
          aliases: ["-m"],
          desc:    "Render in the terminal through mdfried instead of the system viewer"

        example [
          "#{OpenLanes::Agents::Names::RESEARCHER}               # #{OpenLanes::Agents::Names::RESEARCHER}, in the system Markdown viewer",
          "#{OpenLanes::Agents::Names::BACKEND_CODER} -m    # the same, rendered in this terminal by mdfried",
          "                       # every agent, one viewer window each"
        ]

        # The registry instantiates commands bare, so both collaborators
        # default to the real thing; the suite hands in its own to keep
        # viewers from opening on the box running it.
        #
        # @param agents [OpenLanes::Agents::Registry]
        # @param viewer [OpenLanes::Presentation::Viewer]
        def initialize(agents: OpenLanes::Agents.registry, viewer: Presentation.viewer)
          super()
          @agents = agents
          @viewer = viewer
        end

        # @param name [String, nil]
        # @param mdfried [Boolean]
        # @return [void]
        def call(name: nil, mdfried: false, **_options)
          agents = @agents
          found = name ? agents.match(name) : agents.all

          if found.empty?
            known = agents.all.map(&:name).join(", ")
            raise Error, name ? "No agent matches #{name}. Known: #{known}" : "No agent definitions in #{agents.dir}"
          end

          # A fragment that fits several agents is a question, not an order:
          # opening all of them would bury the one that was meant.
          raise Error, "#{name} could be any of #{found.map(&:name).join(", ")} — say which" if name && found.size > 1

          paths = found.map(&:path)
          mdfried ? @viewer.mdfried(paths) : @viewer.open(paths)
        rescue OpenLanes::Error => e
          error(e.message)
          exit 65
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes agents …` — the specialist roster.
    module Agents
      # `openlanes agents list`
      class List < Dry::CLI::Command
        include UI

        desc "List every specialist, what it handles, and what it advances to"

        example ["", "| less -R"]

        # @return [void]
        def call(**) = $stdout.write(OpenLanes::Agents.roster.list)
      end
    end
  end
end

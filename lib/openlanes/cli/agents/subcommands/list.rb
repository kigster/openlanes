# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes agents …` — the specialist roster.
    module Agents
      # `openlanes agents list`
      class List < Dry::CLI::Command
        include UI

        desc "List every specialist, what it handles, and what it advances to, " \
             "then which coding CLIs can take an agent on this machine"

        example ["", "| less -R"]

        # The roster, then the Adapters table (plan 040, D8), probed now: a
        # command run by hand should say what is true this minute, not what
        # the probe thread last wrote.
        #
        # @return [void]
        def call(**)
          $stdout.write(OpenLanes::Agents.roster.list)
          $stdout.write("\n", OpenLanes::Adapters::Report.new(OpenLanes::Adapters.availability).render)
        end
      end
    end
  end
end

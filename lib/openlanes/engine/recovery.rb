# frozen_string_literal: true

module OpenLanes
  module Engine
    # What the harness writes for an agent that cannot write it itself, and
    # how a run picks up the rounds a dead one left behind. Split out of
    # {Dispatcher} (045, A8).
    #
    # - {Records}: the harness's own lines in a plan's `state.json`.
    # - {Stranded}: rounds a dead run started, resumed at the next start.
    module Recovery
      # One agent's round on one plan: what every record is about.
      #
      # @!attribute [r] subject
      #   @return [Plans::Subject]
      # @!attribute [r] agent
      #   @return [Agents::Agent]
      # @!attribute [r] round
      #   @return [Integer]
      Round = Data.define(:subject, :agent, :round)

      # Who the harness signs its own mail as.
      HARNESS = "openlanes"

      # What the harness says when it died under a round.
      DIED = "harness died"
    end
  end
end

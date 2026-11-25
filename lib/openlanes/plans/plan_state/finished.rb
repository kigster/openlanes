# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # When and how a plan finished, which the control room keeps on the
      # board for the rest of the run (and a restarted engine carries the
      # latest one over). Kept here because nothing else records the moment:
      # the folder name says ✅ but not since when, and `pull-requests.md`
      # has no times at all.
      #
      # @!attribute [r] kind
      #   @return [String] one of {FINISH_KINDS}
      # @!attribute [r] at
      #   @return [Time]
      Finished = Data.define(:kind, :at) do
        # @return [Boolean]
        def merged? = kind == "merged"

        # @return [Hash] as `state.json` and the snapshot carry it
        def to_json_h = { "kind" => kind, "at" => at.utc.iso8601 }
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    # Where a plan goes once its rejections reach `merge.max_rejections`
    # (M6): to the arbitrator, `obi-wan-kenobi-arbitrator` (M7, M8), which
    # plan 015 builds.
    #
    # Until then this is the seam it plugs into, and its default only says
    # so. The plan is handled as any other rejection, so nothing waits on a
    # ruling nobody can give yet; holding it under Needs you at the cap is
    # plan 014.02's.
    class Arbitration
      # @param plan [OpenLanes::Plans::Subject]
      # @param count [Integer] rejections so far, hansolo's and chewie's
      # @param max [Integer] `merge.max_rejections`
      # @return [void]
      def call(plan:, count:, max:)
        UI.log("rejected #{count} of #{max}: at the cap, and no arbitrator is built yet (plan 015)",
          level: :warn,
          plan:  plan.feature.ordinal.to_s)
      end
    end
  end
end

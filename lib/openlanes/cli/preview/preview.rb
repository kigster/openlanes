# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes app` — the app a plan builds, run on this machine for the
    # control room's Preview tab (plan 012). See {OpenLanes::Apps}.
    module App
      # Branch names carry the plan: `<user>/NNN.MM-slug` (see {Vcs::Worktree}).
      BRANCH_PLAN = %r{\A[^/]+/(\d{3}\.\d{2})-}

      # The ordinal a run without one is filed under.
      NO_PLAN = "000.00"

      # What every subcommand needs from the registry.
      module Registry
        private

        # @return [OpenLanes::Apps::Ports]
        def registry = OpenLanes::Apps.registry

        # @param plan [String, nil] as typed
        # @return [String, nil] canonical, nil when nothing was typed
        def ordinal_of(plan)
          return nil if plan.nil?

          Plans::Ordinal.parse(plan.to_s)&.to_s || refuse("#{plan} is not a plan number like 012 or 012.00", 64)
        end
      end
    end
  end
end

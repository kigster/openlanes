# frozen_string_literal: true

module OpenLanes
  module Engine
    module Steps
      # Pull requests nobody is working on, kept from going stale (U1 to
      # U4), at most once per {POLL} seconds: GitHub is asked about every
      # rejected pull request, and about every waiting one each time `main`
      # moves. What to do with a conflict is the dispatcher's, since only it
      # starts jobs; this hands each one over.
      class Sweeps
        # @param context [Context]
        # @param resolve [#call] takes the keeper and one {Upkeep::Conflict}
        def initialize(context, resolve:)
          @context = context
          @resolve = resolve
          @interval = Interval.new(POLL)
        end

        # @return [void]
        def call
          upkeep = @context.runner.upkeep or return
          return if @context.runner.dry_run? || !@interval.due?

          keep(upkeep)
        rescue OpenLanes::Error => e
          UI.log("pull requests not kept up this time: #{Steps.first_line(e)}", level: :warn)
        end

        private

        # @param upkeep [Upkeep::Keeper]
        # @return [void]
        def keep(upkeep)
          upkeep.address.each { UI.log(it) }
          sweep = upkeep.sweep(@context.runner.in_scope, busy: @context.busy.call)
          sweep.notes.each { UI.log(it) }
          sweep.conflicts.each { @resolve.call(upkeep, it) }
        end
      end
    end
  end
end

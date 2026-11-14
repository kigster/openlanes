# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What the running agents have written since the last tick, read and
      # kept: each one's latest ledger line and spend into the state file
      # ({Sighting}), its session and journal lines into the plan's
      # `state.json` ({Journal}), and the mail addressed to its plan ({Mail}).
      # It also notices an agent near the end of its clock. Nothing here
      # starts, stops or renames anything.
      class Poll < Step
        # @param desk [Desk]
        def initialize(desk)
          super
          @mail = Mail.new(desk)
          @journal = Journal.new(desk)
          @sighting = Sighting.new(desk, journal: @journal)
        end

        # @return [void] see {Mail#drain_mail}
        def_delegator :@mail, :drain_mail

        # @return [void] see {Journal#call}
        def_delegator :@journal, :call, :record_journal

        # @return [void]
        def poll
          running.each { @sighting.call(it) }
        end

        # Each running agent near the end of its clock asks for more, and is
        # given it once on its own. Read only in the last {Extensions::ASK_AT}
        # seconds, so the folder is looked up then and not on every tick.
        #
        # @return [void]
        def ask_for_time
          return if runner.dry_run?

          running.each do |job|
            left = job.handle.remaining
            next unless left && left <= Extensions::ASK_AT

            subject = fresh(job.task) or next
            extensions.watch(job, subject.feature.path)
          end
        end
      end
    end
  end
end

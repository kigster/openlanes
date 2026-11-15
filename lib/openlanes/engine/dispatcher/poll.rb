# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What the running agents have written since the last tick, read and
      # kept: each one's latest ledger line and spend into the state file
      # ({Sighting}), its session and journal lines into the plan's
      # `state.json` ({Journal}), and the mail addressed to its plan ({Mail}).
      # It also notices an agent near the end of its clock, and moves that
      # clock. Nothing here starts, stops or renames anything.
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

        # Each running agent near the end of its clock is given more, or
        # asked how much it needs ({Extensions::Ladder}). The plan is read
        # only for a job that is due, so its folder is not looked up on
        # every tick of every round.
        #
        # @return [void]
        def ask_for_time
          return if runner.dry_run?

          running.select { ladder.due?(it) }.each do |job|
            subject = fresh(job.task) or next
            granted = ladder.watch(job, subject) or next
            feed.append(:extension, plan: plan_of(job), agent: job.task.agent.name, seconds: granted["seconds"])
          end
        end
      end
    end
  end
end

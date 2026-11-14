# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What a person, or another machine, does to a whole plan while the
      # run is under way: throw its work away, take its claim, stop it, or
      # put it back on the board. Each one stops the plan's agents first and
      # leaves the rest to a later tick, so no command holds the loop while
      # an agent takes its {KILL_GRACE} seconds to go.
      class Lanes < Step
        # @param desk [Desk]
        def initialize(desk)
          super
          @discards = Discards.new(desk)
          @copilot = Copilot.new(desk)
        end

        # @return [void] see {Discards#complete}
        def_delegator :@discards, :complete, :finish_discards

        # The copilot's `/stop NNN` and `/restart NNN`; see {Copilot}.
        def_delegators :@copilot, :stop_plan, :restart_plan

        # Throw a plan's work away (W9): every agent on it is stopped, each with
        # {KILL_GRACE} seconds to finish the line it is writing, and once the
        # last is gone the plan's worktree is reset and its folder sent back
        # to the state that work started from. Plan-wide, because a pair
        # shares one worktree and a reset takes both halves. What can be
        # refused is refused ({Discards#check!}) before any agent is stopped.
        #
        # @param ordinal [#to_s]
        # @return [OpenLanes::Engine::Dispatcher::Discard] finished on a later tick
        # @raise [OpenLanes::Error] with the reason it cannot be done
        def discard(ordinal)
          ordinal = ordinal.to_s
          return discarding[ordinal] if discarding.key?(ordinal)

          jobs = agents_on(ordinal)
          from = @discards.check!(ordinal, jobs)
          jobs.each { |job| Thread.new { job.handle.kill!(grace: KILL_GRACE, reason: :discard) } }
          discarding[ordinal] = Discard.new(ordinal:, from:)
        end

        # Plans whose claim another machine now holds (W26): their agents are
        # stopped, each with {KILL_GRACE} seconds, the plans leave this run,
        # and nothing this node does afterwards signs or renames for them.
        #
        # @param ordinals [Array<String>]
        # @return [void]
        def fence(ordinals)
          ordinals.map(&:to_s).each do |ordinal|
            fenced << ordinal unless fenced.include?(ordinal)
            runner.drop_plan(ordinal)
            agents_on(ordinal).each do |job|
              UI.log("claim lost; stopping", level: :warn, **job.task.log_fields)
              Thread.new { job.handle.kill!(grace: KILL_GRACE, reason: :fenced) }
            end
          end
        end

        private

        def agents_on(ordinal) = running.select { plan_of(it) == ordinal }
      end
    end
  end
end

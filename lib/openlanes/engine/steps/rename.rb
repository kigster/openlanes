# frozen_string_literal: true

module OpenLanes
  module Engine
    module Steps
      # The renames that follow a settle, split out of {Dispatcher} (060,
      # B5a). Today that is a discard (W9) whose agents have all gone: the
      # plan's worktree is reset and its folder sent back to the state its
      # work started from.
      #
      # The dispatcher still owns the table of discards under way, since
      # {Dispatcher#discard} fills it and the busy and quiet checks read it;
      # this step only drains it.
      class Rename
        # The state the discarded work started from: each job's {Dispatcher::Job#from},
        # the state the plan showed when it was picked. Only an agent with
        # `starts_as` moved the folder on, so stepping back from the folder's
        # own state sent every other agent's plan one phase too far (issue
        # #173). A pair can be picked on either side of backend-coder's
        # `starts_as` rename, so the earliest of its starts wins: the one with
        # the longest road ahead of it.
        #
        # @param jobs [Array<#from>]
        # @return [Symbol, nil] nil when no agent was running
        def self.started_from(jobs) = jobs.map(&:from).compact.uniq.max_by { Plans::StateMachine.onward(it).size }

        # @param context [Context]
        # @param discarding [Hash{String => Dispatcher::Discard}] drained in place
        # @param running [#call] the ordinals an agent is still running on
        def initialize(context, discarding:, running:)
          @context = context
          @discarding = discarding
          @running = running
        end

        # A finished discard stays one tick, for {Live::Commands} to reply
        # from, and is dropped on the next.
        #
        # @return [void]
        def call
          @discarding.delete_if { |_, discard| discard.finished? }
          running = @running.call
          @discarding.each_value do |discard|
            next if running.include?(discard.ordinal)

            discard.status, discard.reason = throw_back(discard)
          end
        end

        private

        # @param discard [Dispatcher::Discard]
        # @return [Array(String, String)] status and reason
        def throw_back(discard)
          ordinal = discard.ordinal
          subject = Plans::Tree.new(dir: @context.runner.tree.dir).find(Plans::Ordinal.parse(ordinal)) or
            return ["refused", "#{ordinal}'s folder vanished"]
          ["done", "#{ordinal} #{retreat(subject, discard.from)}"]
        rescue OpenLanes::Error => e
          ["refused", "#{ordinal}'s agents were stopped, but: #{e.message}"]
        end

        # @param subject [Plans::Subject]
        # @param start [Symbol, nil] see {Dispatcher::Discard#from}
        # @return [String] what the reset and the rename did
        def retreat(subject, start)
          ordinal = subject.feature.ordinal.to_s
          reset = @context.runner.worktree.reset(subject.feature)
          from = subject.status
          to = subject.machine.retreat!(start)
          @context.reopen.call(ordinal)
          UI.log("discarded: #{from} -> #{to}", plan: ordinal)
          moved = to.key == from.key ? "stays at #{to}, where its work started" : "went back from #{from} to #{to}"
          "#{reset ? "reset" : "had no worktree to reset"}, and #{moved}"
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    # Blocked plans whose every question has an answer, handed to the agent
    # that handles their state, the way `openlanes unblock` hands them over
    # (W10), split out of {Dispatcher} (045, A8).
    #
    # - {Drainer}: finds the answered plans each tick and drains each on a
    #   thread of its own; the dispatcher's one face onto the rest.
    # - {Settler}: what follows a drain, good or bad.
    # - {Reopener}: an answer the broker would not take goes back to the page.
    module Unblocking
      # One drain under way.
      #
      # @!attribute [r] ordinal
      #   @return [String]
      # @!attribute [r] thread
      #   @return [Thread]
      # @!attribute [r] outcome
      #   @return [Lifecycle::Unblocker::Outcome, Exception, nil] once it ended
      # @!attribute [r] agent
      #   @return [String] the broker's name
      # @!attribute [r] rounds
      #   @return [Integer] the broker's journal rounds before this drain
      Drain = Struct.new(:ordinal, :thread, :outcome, :agent, :rounds)

      module_function

      # @param context [Steps::Context]
      # @param history [#call] takes an ordinal and forgets its Blocked rounds,
      #   so the plan's agents get their rounds back
      # @return [Drainer]
      def drainer(context, history:)
        Drainer.new(context, settler: Settler.new(context, history:, reopener: Reopener.new))
      end
    end
  end
end

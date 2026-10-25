# frozen_string_literal: true

module OpenLanes
  module Engine
    # The tick's polls over GitHub, one class each, split out of
    # {Dispatcher} (045, A8). Each answers `#call` once a tick; the
    # dispatcher decides when, and only it assigns or renames.
    #
    # - {Merges}: assessed 🏁 plans moved on by their merges (P1 to P5).
    # - {Sweeps}: pull requests nobody is working on kept fresh (U1 to U4).
    # - {Watch}: pull requests a person owes, polled off the tick thread (M4).
    #
    # None of them knows the dispatcher: what they need of it arrives as a
    # {Context} of callables.
    module Steps
      # Seconds between passes over the pull requests: GitHub is asked up to
      # three times per pull request on each.
      POLL = 30

      # What a step is handed by the dispatcher.
      #
      # @!attribute [r] runner
      #   @return [Runner]
      # @!attribute [r] busy
      #   @return [#call] the ordinals nothing may touch now
      # @!attribute [r] wake
      #   @return [#call] asks for a rescan on the next tick
      # @!attribute [r] reopen
      #   @return [#call] takes an ordinal off the plans finished in this run
      Context = Data.define(:runner, :busy, :wake, :reopen)

      module_function

      # @param error [Exception]
      # @return [String] the first line of its message
      def first_line(error) = error.message.lines.first.to_s.strip
    end
  end
end

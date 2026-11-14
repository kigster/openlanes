# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # The keywords a {Dispatcher} is built with, gathered once at the entry
      # point so no method past it takes more than four parameters (A8).
      #
      # @!attribute runner [OpenLanes::Engine::Runner]
      # @!attribute state [OpenLanes::Engine::StateFile, nil] restart state; nil under a dry run
      # @!attribute rounds [Integer, nil] `--rounds`
      # @!attribute sleeper [#call, nil] waits a tick; nil sleeps on the clock
      # @!attribute clock [#now, #sleep]
      # @!attribute on_board [Proc, nil] receives a {Board} each tick
      # @!attribute stay [Boolean] keep running past every fixed point
      # @!attribute rescan [Integer] idle ticks between rescans while staying
      # @!attribute watch [OpenLanes::Engine::PrWatch, nil]
      # @!attribute converter [#call, nil] rewrites prose questions into choices (D9)
      # @!attribute extensions [OpenLanes::Engine::Extensions, nil]
      # @!attribute journal [OpenLanes::Engine::EventJournal, nil]
      # @!attribute budget [OpenLanes::Engine::Budget, nil]
      Options = Data.define(:runner,
        :state,
        :rounds,
        :sleeper,
        :clock,
        :on_board,
        :stay,
        :rescan,
        :watch,
        :converter,
        :extensions,
        :journal,
        :budget) do
        # The defaults {Dispatcher#initialize} has always had. `converter` is
        # asked of {Live} only when none is given, as before.
        #
        # @return [Options]
        def self.with_defaults(runner:, clock:, converter: Live.choice_converter, **rest)
          new(runner:, clock:, converter:, **self::DEFAULTS.merge(rest))
        end

        # @return [Desk::Setup] what the desk is built from
        def desk_setup = Desk::Setup.new(runner:, state:, rounds:, stay:, journal:, extensions:, budget:)
      end

      # Every optional keyword's default, but `converter`, which is computed.
      Options::DEFAULTS = { state: nil, rounds: nil, sleeper: nil, on_board: nil, stay: false, rescan: RESCAN,
                            watch: nil, extensions: nil, journal: nil, budget: nil }.freeze
    end
  end
end

# frozen_string_literal: true

require "forwardable"

module OpenLanes
  module Engine
    class Dispatcher
      # One part of the tick, split out of {Dispatcher} (plan 060, item 5):
      # {Assign} picks who works what, {Start} sets them going, {Poll} reads
      # what the running ones have written, {Settle} makes an attempt of each
      # that finished, and {Rename} moves the folder a finished round earned.
      #
      # A step keeps no copy of the run's state. It reads and writes the
      # {Desk} it was handed, under the names the loop itself uses, so a
      # method reads the same wherever it lives. A step that needs another
      # is handed it by the {Dispatcher}, which alone knows the order.
      class Step
        extend Forwardable

        def_delegators :@desk, *Desk.public_instance_methods(false)
        private(*Desk.public_instance_methods(false))

        # @param desk [Desk]
        def initialize(desk)
          @desk = desk
        end
      end
    end
  end
end

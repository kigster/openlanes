# frozen_string_literal: true

module OpenLanes
  module Execution
    # Waiting on a child with a limit: the wait the copilot's operator made
    # for itself, shared since the unblocker's interview needs the same one.
    # A model run that hangs must not hold the conversation for ever, and an
    # interview's run that outlived its lock let a second one start beside it.
    #
    # Unlike {Clock}, nothing here is advisory: these runs write nothing, so
    # there is no ledger line to wait for before ending them.
    module Deadline
      # Read the child's output in the block, then wait for it, ending it
      # with {Child#terminate} once +seconds+ have passed.
      #
      # @param child [OpenLanes::Execution::Child]
      # @param seconds [Numeric] how long the child may run
      # @yield reads the child's output, on the caller's thread
      # @return [Array(Process::Status, Boolean)] how the child ended, and
      #   whether it was ended for running out of time
      def self.wait(child, seconds)
        late = false
        watchdog = Thread.new do
          sleep(seconds)
          late = true
          child.terminate
        end
        yield
        [child.wait, late]
      ensure
        watchdog&.kill
      end
    end
  end
end

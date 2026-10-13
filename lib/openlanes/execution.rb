# frozen_string_literal: true

module OpenLanes
  # One agent invocation: the child process, its clock, the control file it
  # polls, and the transcript it streams back. The autonomy boundary lives
  # here, because this is the only place a coding agent is started.
  module Execution
    module_function

    # @return [OpenLanes::Execution::Executor]
    def executor(**) = Executor.new(**)

    # Run the block with Ctrl-C turned into a cooperative interrupt.
    #
    # @param signals [Array<String>] handled as Ctrl-C is
    # @return [Object] whatever the block returns
    def on_interrupt(signals: %w[INT], &) = Control.on_interrupt(signals, &)
  end
end

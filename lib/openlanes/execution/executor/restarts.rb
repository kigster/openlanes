# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # How a first start may be made again: the session it carried on, a
      # fresh start for when that session is gone, and what a throttled
      # start is started with again. An agent taken back after a restart
      # has none of them.
      #
      # @!attribute [r] resume
      #   @return [String, nil] the session id the first start carried on
      # @!attribute [r] relaunch
      #   @return [#call, nil] starts the invocation fresh
      # @!attribute [r] again
      #   @return [#call, nil] starts it again as it was first started
      Restarts = Data.define(:resume, :relaunch, :again) do
        def initialize(resume: nil, relaunch: nil, again: nil) = super
      end
    end
  end
end

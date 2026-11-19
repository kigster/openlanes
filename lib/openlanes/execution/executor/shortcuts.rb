# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The class methods callers reached on `Executor` before the cut, each
      # answering through the collaborator that now owns the body. `Executor`
      # extends it, so `Executor.deadline(clock)` still works as it did.
      module Shortcuts
        # @see Credentials.foreign
        def foreign_credentials(env = ENV) = Credentials.foreign(env)

        # @see Deadline.of
        def deadline(clock) = Deadline.of(clock)

        # @see Spending.nothing?
        def spent_nothing?(spent = nil, **) = Spending.nothing?(spent, **)
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Locking
    # The contract every locking adapter keeps. {Shell} is the one that runs
    # the `alock` command; an adapter over agent-lock's Ruby API keeps the same
    # three methods. Callers depend on these and nothing else.
    #
    # Every adapter is shared by every thread of the process, so each method
    # must be safe to call from several at once.
    module Adapter
      # @param root [String] the checkout whose register is read
      # @return [Array<Lock>] every active lock
      # @raise [Unavailable] when the register cannot be reached
      # @raise [Unreadable] when it answers with something unreadable
      def list(root) = raise(NotImplementedError)

      # @param scope [String] a path or glob, relative to +dir+
      # @param intent [String]
      # @param dir [String] where the scope is read from
      # @param as [String] the holder's agent id
      # @return [Outcome]
      # @raise [Unavailable]
      def acquire(scope, intent, dir:, as:) = raise(NotImplementedError)

      # @param scope [String]
      # @param dir [String]
      # @param as [String]
      # @return [Outcome]
      # @raise [Unavailable]
      def release(scope, dir:, as:) = raise(NotImplementedError)
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Locking
    # The contract every locking adapter keeps. {Shell} is the one that runs
    # the `alock` command; an adapter over agent-lock's Ruby API keeps the same
    # three methods. Callers depend on these and nothing else.
    #
    # Rules an adapter must keep, because callers rely on them:
    #
    # - Thread safety. One adapter is shared by every thread of the process,
    #   so each method must be safe to call from several at once, and must
    #   return in bounded time: callers hold their own mutex around {#list}.
    # - Lifetime. A lock lives no longer than this process. {Shell} gets that
    #   from alock, which pins a lock to the process that ran it. An
    #   in-process adapter must name this process as the session, not its
    #   parent (agent-lock's `Identity` starts from `Process.ppid`), or the
    #   engine's locks outlive the engine.
    # - {Unavailable} is permanent. Raise it only when the register cannot
    #   exist on this machine (alock not installed), since callers turn
    #   locking off for the rest of the run. A fault that may pass (Redis not
    #   answering, a timeout) is {Unreadable} from {#list} and a `:failed`
    #   {Outcome} from {#acquire} and {#release}.
    module Adapter
      # @param root [String] the checkout whose register is read
      # @return [Array<Lock>] every active lock
      # @raise [Unavailable] when there is no register at all
      # @raise [Unreadable] when it could not be read this time
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

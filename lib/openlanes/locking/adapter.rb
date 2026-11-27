# frozen_string_literal: true

module OpenLanes
  module Locking
    # The contract every locking adapter keeps. {Distributed}, over
    # agent-lock's Ruby API on Redis, is the only one openlanes runs; the
    # specs put doubles in its place. Callers depend on these three methods
    # and nothing else.
    #
    # Rules an adapter must keep, because callers rely on them:
    #
    # - Thread safety. One adapter is shared by every thread of the process,
    #   so each method must be safe to call from several at once, and must
    #   return in bounded time: callers hold their own mutex around {#list}.
    # - Lifetime. A lock lives no longer than this process. An in-process
    #   adapter must name this process as the session, not its parent
    #   (agent-lock's `Identity` starts from `Process.ppid`), or the engine's
    #   locks outlive the engine.
    # - Redis only. A lock in agent-lock's file store is invisible to every
    #   other machine, so no adapter falls back to it.
    # - No fault is permanent. Redis not answering, or a timeout, is
    #   {Unreadable} from {#list} and a `:failed` {Outcome} from {#acquire}
    #   and {#release}; callers ask again on the next call.
    module Adapter
      # @param root [String] the checkout whose register is read
      # @return [Array<Lock>] every active lock
      # @raise [Unreadable] when it could not be read this time
      def list(root) = raise(NotImplementedError)

      # @param scope [String] a path or glob, relative to +dir+
      # @param intent [String]
      # @param dir [String] where the scope is read from
      # @param as [String] the holder's agent id
      # @return [Outcome]
      def acquire(scope, intent, dir:, as:) = raise(NotImplementedError)

      # @param scope [String]
      # @param dir [String]
      # @param as [String]
      # @return [Outcome]
      def release(scope, dir:, as:) = raise(NotImplementedError)
    end
  end
end

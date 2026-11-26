# frozen_string_literal: true

require "socket"

module OpenLanes
  # The alock register (the agent-lock gem), behind one adapter. Every call
  # openlanes makes to alock goes through {.adapter}; nothing else runs it.
  #
  # It sits below both {Engine} and {Execution}. The engine takes the plan
  # folder claims; the executor tells each agent whose child it is. When the
  # holder id lived in `Engine`, `Execution::Launcher` had to call up into
  # `Engine`, which already depends on `Execution`, and the two namespaces
  # formed a cycle. Both now depend on this one instead.
  #
  # {Shell} runs the `alock` command. An adapter over agent-lock's Ruby API
  # can take its place through {.adapter=}, with no caller changing.
  module Locking
    # The environment variable alock reads a holder's parent from.
    PARENT_VARIABLE = "AGENT_PARENT_ID"

    @mutex = Mutex.new
    @adapter = nil

    class << self
      # The agent id this openlanes process signs its claims with. Agents it
      # starts get it as {PARENT_VARIABLE}, so alock reads their claims inside
      # a plan folder the engine holds as a child's, not as a stranger's.
      #
      # @return [String] `openlanes@<host>:<pid>`
      def holder = "openlanes@#{Socket.gethostname}:#{Process.pid}"

      # @return [Hash{String => String}] what an agent's process needs added
      #   to its environment to be this process's child in alock
      def child_environment = { PARENT_VARIABLE => holder }

      # The process-wide adapter, made on first use.
      #
      # @return [#list, #acquire, #release] see {Adapter}
      def adapter = @mutex.synchronize { @adapter ||= Shell.new }

      # @param adapter [#list, #acquire, #release, nil] nil goes back to {Shell}
      # @return [void]
      def adapter=(adapter)
        @mutex.synchronize { @adapter = adapter }
      end
    end
  end
end

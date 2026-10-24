# frozen_string_literal: true

require "digest"

module OpenLanes
  module Events
    # The idempotency key of an event.
    #
    # Replaying the same invocation must give the same id, so a duplicate
    # line is dropped at read time instead of counted twice. `RunState#seq`
    # cannot serve: it is monotonic inside one node only, and two nodes
    # would reuse it. `seq` here tells apart two events of one kind on one
    # invocation, such as two `human_answered` for B1 and B2.
    module Identity
      module_function

      # @param node [String] {Live::Node#id}
      # @param checkout [String] {Live::Node#checkout_id}
      # @param plan [String, nil] `NNN.MM`
      # @param round [Integer, nil]
      # @param agent [String, nil]
      # @param invocation_start [String, Time, nil]
      # @param kind [String]
      # @param seq [Object] whatever tells two same-kind events apart
      # @return [String] 64 hex digits
      def event_id(node:, checkout:, plan:, round:, agent:, invocation_start:, kind:, seq: 0)
        start = invocation_start.is_a?(Time) ? invocation_start.utc.iso8601(3) : invocation_start
        Digest::SHA256.hexdigest([node, checkout, plan, round, agent, start, kind, seq].join("\u001f"))
      end
    end
  end
end

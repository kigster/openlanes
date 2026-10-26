# frozen_string_literal: true

module OpenLanes
  module Live
    # Who holds a plan's claim, decoded from the holding node's
    # {Node#name} (`id:checkout_id[:role]`), so a refusal can say "openlanes
    # run (pid 4242)" rather than print a digest.
    Holder = Data.define(:machine, :checkout_id, :role) do
      # @param name [String] a {Node#name}
      # @return [OpenLanes::Live::Holder]
      def self.parse(name)
        machine, checkout_id, role = name.to_s.split(":", 3)
        new(machine:, checkout_id:, role:)
      end

      # @return [Integer, nil] the pid of the `openlanes run` holding it, nil for a factory
      def run_pid = role&.start_with?("run-") ? Integer(role.delete_prefix("run-"), exception: false) : nil

      # The holder in words, as seen from this process's node.
      #
      # @param node [OpenLanes::Live::Node] the node asking
      # @return [String]
      def describe(from:)
        mine = machine == from.id
        where = mine ? "this machine" : "another machine"
        return "openlanes run (pid #{run_pid}) on #{where}" if run_pid
        # A role this code does not know yet is named, never mistaken for the factory.
        return "a #{role} node on #{where}" if role
        return "this checkout's factory (openlanes start)" if mine && checkout_id == from.checkout_id

        "the factory on #{where}"
      end
    end
  end
end

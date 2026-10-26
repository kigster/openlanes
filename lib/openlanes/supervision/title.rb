# frozen_string_literal: true

module OpenLanes
  module Supervision
    # The name a factory process shows in `ps` (S5): `openlanes-<role>
    # [<project>]`, then its live status. `pgrep -f openlanes-` finds every
    # one, the project tells two factories apart, and {Probe} reads the
    # prefix back as half of a process's identity.
    class Title
      # @param role [String]
      # @param root [String]
      # @return [String]
      def self.prefix(role, root) = "openlanes-#{role} [#{File.basename(root)}]"

      # @param seconds [Integer]
      # @return [String] 45s, 12m, 2h or 3d: one unit, for a title or a table
      def self.duration(seconds)
        return "#{seconds}s" if seconds < 60
        return "#{seconds / 60}m" if seconds < 3600
        return "#{seconds / 3600}h" if seconds < 86_400

        "#{seconds / 86_400}d"
      end

      # A supervisor's status: `up 2h, 1 restart, web down`.
      #
      # @param uptime [Integer] seconds it has run
      # @param restarts [Integer] crashes it restarted a child after
      # @param down [Array<String>] roles it gave up on
      # @return [String]
      def self.supervising(uptime:, restarts:, down:)
        status = "up #{duration(uptime)}, #{restarts} restart#{"s" unless restarts == 1}"
        down.empty? ? status : "#{status}, #{down.join(" and ")} down"
      end

      # @param role [String]
      # @param root [String]
      # @param setter [#call] `Process.setproctitle` by default
      def initialize(role:, root:, setter: ::Process.method(:setproctitle))
        @prefix = self.class.prefix(role, root)
        @setter = setter
      end

      # @param status [String, nil]
      # @return [String] the title set
      def set(status = nil)
        title = [@prefix, status].compact.join(" ")
        @setter.call(title)
        title
      end
    end
  end
end

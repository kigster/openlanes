# frozen_string_literal: true

require "digest"
require "etc"
require "socket"

module OpenLanes
  module Live
    # This machine and user, as other machines sharing the Redis see it (W26).
    #
    # The id is a digest of `user@host` so keys are short and uniform, not to
    # hide anyone: the plain names travel beside it. The checkout id keeps
    # two clones on one machine apart.
    #
    # @!attribute [r] id
    #   @return [String] 24 hex digits of SHA-256 of `user@host`
    # @!attribute [r] user
    #   @return [String]
    # @!attribute [r] host
    #   @return [String]
    # @!attribute [r] ip
    #   @return [String, nil] shown, never used to identify the node
    # @!attribute [r] checkout
    #   @return [String] the checkout's path, `$HOME` written as `~`
    # @!attribute [r] checkout_id
    #   @return [String] 12 hex digits of SHA-256 of the checkout's realpath
    # @!attribute [r] role
    #   @return [String, nil] nil for the checkout's factory; `run-<pid>` for
    #     an `openlanes run` beside it, which must be a node of its own: with
    #     the factory's name its claims would be the factory's too, and the
    #     factory would take the plans the run was started to hold (O1)
    Node = Data.define(:id, :user, :host, :ip, :checkout, :checkout_id, :role) do
      # @param role [String, nil]
      def initialize(role: nil, **) = super

      # @return [String] `<id>:<checkout_id>`, or `<id>:<checkout_id>:<role>`,
      #   what keys and claims carry. The machine stays the first part, which
      #   is all {Keys#apps} and the board read of it.
      def name = [id, checkout_id, role].compact.join(":")

      # @return [String] `user@host`, what the page shows
      def label = "#{user}@#{host}"

      # The `Node` of `web/src/api/types.ts`.
      #
      # @param heartbeat_at [Time]
      # @param me [Boolean]
      # @return [Hash]
      def wire(heartbeat_at:, me: true)
        { id:, user:, host:, ip:, checkout:, heartbeat_at: heartbeat_at.utc.iso8601, me: }
      end
    end

    class Node
      # Hex digits kept of each digest.
      ID_LENGTH = 24
      CHECKOUT_LENGTH = 12

      # A declared `user@host`: one of each, no spaces, no second `@`.
      IDENTITY = /\A(?<user>[^@\s]+)@(?<host>[^@\s]+)\z/

      # A declared identity that is not `user@host`.
      class Invalid < ArgumentError; end

      class << self
        # This checkout as a machine of another name: `openlanes web --demo
        # --identity demo@second-machine` registers as a second machine on the
        # same Redis and repository, through the same digest every process
        # is already named by, so nothing reads a second naming scheme.
        #
        # @param identity [String] `user@host`
        # @param root [String] the checkout
        # @return [OpenLanes::Live::Node]
        # @raise [Invalid]
        def declared(identity, root:, **)
          match = IDENTITY.match(identity.to_s.strip) or raise Invalid, "an identity is user@host, not #{identity.inspect}"
          current(root:, user: match[:user], host: match[:host], **)
        end

        # @param root [String] the checkout
        # @param user [String]
        # @param host [String]
        # @param home [String]
        # @param ip [String, nil]
        # @param role [String, nil] see {Node#role}
        # @return [OpenLanes::Live::Node]
        def current(root:, user: login, host: Socket.gethostname, home: Dir.home, ip: address, role: nil)
          real = File.realpath(root)
          new(id: digest("#{user}@#{host}", ID_LENGTH),
            user:,
            host:,
            ip:,
            checkout: tilde(real, home),
            checkout_id: digest(real, CHECKOUT_LENGTH),
            role:)
        end

        # @param text [String]
        # @param length [Integer]
        # @return [String]
        def digest(text, length) = Digest::SHA256.hexdigest(text)[0, length]

        # @return [String]
        def login = Etc.getlogin || ENV.fetch("USER", "unknown")

        # The first address that is neither loopback nor link-local: the one
        # other machines on the network most likely reach this one by.
        #
        # @return [String, nil]
        def address
          Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? && !a.ipv4_multicast? }&.ip_address
        end

        # @param path [String]
        # @param home [String]
        # @return [String]
        def tilde(path, home) = path == home || path.start_with?("#{home}/") ? "~#{path.delete_prefix(home)}" : path
      end
    end
  end
end

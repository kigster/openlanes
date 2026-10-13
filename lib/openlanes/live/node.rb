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
    Node = Data.define(:id, :user, :host, :ip, :checkout, :checkout_id) do
      # @return [String] `<id>:<checkout_id>`, what keys and claims carry
      def name = "#{id}:#{checkout_id}"

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

      class << self
        # @param root [String] the checkout
        # @param user [String]
        # @param host [String]
        # @param home [String]
        # @return [OpenLanes::Live::Node]
        def current(root:, user: login, host: Socket.gethostname, home: Dir.home, ip: address)
          real = File.realpath(root)
          new(id: digest("#{user}@#{host}", ID_LENGTH),
            user:,
            host:,
            ip:,
            checkout: tilde(real, home),
            checkout_id: digest(real, CHECKOUT_LENGTH))
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

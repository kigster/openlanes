# frozen_string_literal: true

require "ipaddr"
require "socket"

module OpenLanes
  module Web
    # The addresses one server listens on, and what follows from them: the
    # Host headers it answers, the URLs it prints, the one a browser opens.
    #
    # Loopback, {HOST}, unless told otherwise (W3). The page can stop agents
    # and answer their questions, and has no login, so listening beyond this
    # machine is something a person asks for by name, and is warned about.
    #
    #   listen = Listen.parse("0.0.0.0")
    #   listen.public?             # => true
    #   listen.urls(11_000)        # => ["http://192.168.1.20:11000", ...]
    #   listen.browse_url(11_000)  # => "http://127.0.0.1:11000"
    Listen = Data.define(:ips) do
      # @return [Boolean] whether anything off this machine can reach it
      def public? = ips.any? { !IPAddr.new(it).loopback? }

      # @return [Array<String>] the addresses past loopback, as given
      def public_ips = ips.reject { IPAddr.new(it).loopback? }

      # Where this machine's browser opens the page: loopback, which every
      # wildcard listener also answers on, else the first address given.
      #
      # @param port [Integer]
      # @return [String]
      def browse_url(port)
        ip = ips.find { Listen.wildcard?(it) || IPAddr.new(it).loopback? } || ips.first
        Listen.url(if Listen.wildcard?(ip)
                     IPAddr.new(ip).ipv6? ? "::1" : HOST
                   else
                     ip
                   end,
          port)
      end

      # Every URL the page answers on, a wildcard spelled out as this
      # machine's own addresses, since `http://0.0.0.0` opens nothing.
      #
      # @param port [Integer]
      # @param addresses [Array<String>] this machine's interface addresses
      # @return [Array<String>]
      def urls(port, addresses: Listen.addresses) = reached(addresses).map { Listen.url(it, port) }

      # The Host headers answered beside loopback, which {App} always
      # permits: each address listened on, a wildcard's interfaces, and this
      # machine's name. Anything else is refused, so a page on another site
      # still cannot reach the server through DNS rebinding.
      #
      # @param addresses [Array<String>]
      # @param hostname [String]
      # @return [Array<String, IPAddr>]
      def permitted_hosts(addresses: Listen.addresses, hostname: Socket.gethostname)
        return [] unless public?

        names = [hostname, hostname.split(".").first].uniq
        names + reached(addresses).map { IPAddr.new(it) }
      end

      private

      # @param addresses [Array<String>]
      # @return [Array<String>] the addresses listened on, each wildcard
      #   replaced by the interface addresses it answers on
      def reached(addresses) = ips.flat_map { Listen.wildcard?(it) ? Listen.covered(it, addresses) : [it] }.uniq
    end

    class Listen
      # Raised for an address that is not one.
      class Invalid < OpenLanes::Error; end

      # What `-I` stands for.
      EVERYWHERE = "0.0.0.0"

      class << self
        # @param text [String, nil] comma-separated addresses; blank for {HOST}
        # @return [Listen]
        # @raise [Invalid] naming the address that is not one
        def parse(text)
          ips = text.to_s.split(",").map(&:strip).reject(&:empty?)
          ips = [HOST] if ips.empty?
          ips.each do |ip|
            IPAddr.new(ip)
          rescue IPAddr::Error
            raise Invalid, "#{ip.inspect} is not an IP address"
          end
          new(ips: ips.uniq)
        end

        # @param ip [String]
        # @return [Boolean] whether it means every interface
        def wildcard?(ip) = IPAddr.new(ip).to_i.zero?

        # @param ip [String]
        # @param port [Integer]
        # @return [String]
        def url(ip, port) = "http://#{IPAddr.new(ip).ipv6? ? "[#{ip}]" : ip}:#{port}"

        # The interface addresses a wildcard answers on. `0.0.0.0` is IPv4
        # only; `::` is both, because Ruby's TCPServer leaves IPV6_V6ONLY
        # off, so Linux and macOS hand it IPv4 clients too. Treating `::` as
        # IPv6 alone refused an IPv4 LAN client's Host header with a 403.
        #
        # @param wildcard [String] `0.0.0.0` or `::`
        # @param addresses [Array<String>]
        # @return [Array<String>]
        def covered(wildcard, addresses)
          return addresses if IPAddr.new(wildcard).ipv6?

          addresses.select { IPAddr.new(it).ipv4? }
        end

        # This machine's interface addresses, loopback first, link-local
        # IPv6 left out: it needs a zone to be dialed, which no URL carries.
        #
        # @return [Array<String>]
        def addresses
          Socket.ip_address_list.reject(&:ipv6_linklocal?).map(&:ip_address).sort_by { IPAddr.new(it).loopback? ? 0 : 1 }
        end
      end
    end
  end
end

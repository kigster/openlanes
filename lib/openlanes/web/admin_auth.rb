# frozen_string_literal: true

require "ipaddr"
require "rack/auth/basic"
require "rack/utils"

module OpenLanes
  module Web
    # Basic auth for every request from off this machine. The page can stop
    # agents, answer their questions and message them, so a server listening
    # past loopback is refused unless it is given credentials
    # (`--admin-credentials`), and this asks for them.
    #
    # A request from loopback passes untouched: it already reached the
    # machine, the browser `openlanes start` opens is on it, and so is the
    # launcher's `/healthz` probe.
    #
    #   use AdminAuth, credentials: AdminAuth::Credentials.parse("admin:s3cret")
    class AdminAuth
      # Where `openlanes run` hands its server the credentials. argv is
      # world-readable through `ps`; a child's environment is not.
      ENV_NAME = "OPENLANES_ADMIN_CREDENTIALS"

      # What the browser's login prompt names.
      REALM = "openlanes control room"

      # Raised for credentials that are not `USER:PASSWORD`.
      class Invalid < OpenLanes::Error; end

      # One user and one password. The password may itself hold a colon;
      # the user may not, since Basic auth splits at the first one.
      Credentials = Data.define(:user, :password) do
        # @param user [String]
        # @param password [String]
        # @return [Boolean] whether both match, compared in constant time
        def match?(user, password)
          # Both compared, always, so the time taken says nothing about
          # which of the two was wrong.
          [Rack::Utils.secure_compare(self.user, user.to_s),
           Rack::Utils.secure_compare(self.password, password.to_s)].all?
        end

        # Never the password, so a credential that reaches a log or an
        # exception message leaks nothing.
        #
        # @return [String]
        def inspect = "#<#{self.class.name} user=#{user.inspect}>"
        alias_method :to_s, :inspect
      end

      class << self
        # @param text [String] `USER:PASSWORD`
        # @return [Credentials]
        # @raise [Invalid] when either half is missing
        def parse(text)
          user, password = text.to_s.split(":", 2)
          unless user.to_s.strip.empty? || password.to_s.empty?
            return Credentials.new(user: user.strip, password:)
          end

          raise Invalid, "takes USER:PASSWORD, both non-empty"
        end

        # @param address [String, nil] `REMOTE_ADDR`
        # @return [Boolean] whether it is this machine, IPv4-mapped IPv6 included
        def loopback?(address)
          ip = IPAddr.new(address.to_s)
          ip = ip.native if ip.ipv4_mapped?
          ip.loopback?
        rescue IPAddr::Error
          false
        end
      end

      # @param app [#call]
      # @param credentials [Credentials]
      def initialize(app, credentials:)
        @app = app
        @credentials = credentials
      end

      # @param env [Hash] the Rack environment
      # @return [Array] the Rack response
      def call(env)
        return @app.call(env) if self.class.loopback?(env["REMOTE_ADDR"])

        auth = Rack::Auth::Basic::Request.new(env)
        return challenge unless auth.provided? && auth.basic? && @credentials.match?(*auth.credentials)

        env["REMOTE_USER"] = auth.username
        @app.call(env)
      end

      private

      # @return [Array] a 401 the browser answers with its login prompt
      def challenge
        [401,
         { "content-type" => "text/plain", "content-length" => "0", "www-authenticate" => %(Basic realm="#{REALM}") },
         []]
      end
    end
  end
end

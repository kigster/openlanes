# frozen_string_literal: true

require "rack/test"

# Basic auth in front of the control room, for requests from off this
# machine only. Driven through rack-test with REMOTE_ADDR set per request.
RSpec.describe OpenLanes::Web::AdminAuth do
  include Rack::Test::Methods

  let(:credentials) { described_class.parse("admin:s3:cret") }
  let(:inner) { ->(env) { [200, { "content-type" => "text/plain" }, [env["REMOTE_USER"].to_s]] } }
  let(:app) { described_class.new(inner, credentials:) }

  def from(address, login: nil)
    basic_authorize(*login) if login
    get "/api/board", {}, "REMOTE_ADDR" => address
    last_response
  end

  describe ".parse" do
    it "splits at the first colon, so a password may hold one" do
      expect([credentials.user, credentials.password]).to eq(%w[admin s3:cret])
    end

    it "refuses a missing user or password" do
      %w[admin admin: :secret].push("", nil).each do
        expect { described_class.parse(it) }.to raise_error(described_class::Invalid, /USER:PASSWORD/)
      end
    end
  end

  it "never shows the password when inspected or printed" do
    expect([credentials.inspect, credentials.to_s, [credentials].inspect].join).not_to include("s3:cret")
  end

  describe "a request from this machine" do
    it "passes with no login, over IPv4, IPv6 and IPv4-mapped IPv6" do
      expect(%w[127.0.0.1 ::1 ::ffff:127.0.0.1].map { from(it).status }).to eq([200, 200, 200])
    end
  end

  describe "a request from another machine" do
    it "is asked to log in" do
      response = from("192.168.1.20")
      expect([response.status, response.headers["www-authenticate"]])
        .to eq([401, %(Basic realm="#{described_class::REALM}")])
    end

    it "passes with the login, and names the user to the app" do
      response = from("192.168.1.20", login: %w[admin s3:cret])
      expect([response.status, response.body]).to eq([200, "admin"])
    end

    it "is refused a wrong password or a wrong user" do
      expect([from("192.168.1.20", login: %w[admin nope]).status,
              from("10.0.0.5", login: %w[root s3:cret]).status]).to eq([401, 401])
    end

    it "is refused a login that is not Basic" do
      header "Authorization", "Bearer abc"
      expect(from("192.168.1.20").status).to eq(401)
    end

    it "is asked to log in when its address cannot be read" do
      expect(from("not-an-address").status).to eq(401)
    end
  end

  describe "in front of the app" do
    let(:store) { OpenLanes::Live.memory_store }
    let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
    let(:context) do
      OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store),
        keys:,
        plans_dir: Dir.tmpdir,
        url: "memory://",
        listen: OpenLanes::Web::Listen.parse("0.0.0.0"),
        credentials:)
    end
    let(:app) { OpenLanes::Web.app(context) }

    it "guards every route a server with credentials serves" do
      get "/healthz", {}, "REMOTE_ADDR" => "192.168.1.20", "HTTP_HOST" => "localhost"
      expect(last_response.status).to eq(401)
    end

    it "lets loopback through to the routes" do
      get "/healthz", {}, "REMOTE_ADDR" => "127.0.0.1", "HTTP_HOST" => "localhost"
      expect(last_response.status).to eq(200)
    end
  end
end

# frozen_string_literal: true

require "socket"

RSpec.describe OpenLanes::Apps::Framing do
  let(:origin) { "http://127.0.0.1:11000" }

  describe ".verdict" do
    {
      "no header at all"                                      => [{}, :frame],
      "X-Frame-Options: DENY"                                 => [{ "X-Frame-Options" => "DENY" }, :window],
      "X-Frame-Options: SAMEORIGIN, whose origin differs"     => [{ "x-frame-options" => "sameorigin" }, :window],
      "X-Frame-Options: ALLOW-FROM, which browsers ignore"    => [{ "X-Frame-Options" => "ALLOW-FROM http://x" }, :frame],
      "frame-ancestors 'none'"                                => [{ "Content-Security-Policy" => "frame-ancestors 'none'" }, :window],
      "frame-ancestors 'self', the app's own origin"          => [{ "Content-Security-Policy" => "default-src 'self'; frame-ancestors 'self'" }, :window],
      "frame-ancestors naming the control room"               => [{ "Content-Security-Policy" => "frame-ancestors 'self' http://127.0.0.1:11000" }, :frame],
      "frame-ancestors naming the host with any port"         => [{ "Content-Security-Policy" => "frame-ancestors 127.0.0.1:*" }, :frame],
      "frame-ancestors naming the host on the default port"   => [{ "Content-Security-Policy" => "frame-ancestors http://127.0.0.1" }, :window],
      "frame-ancestors with a scheme source"                  => [{ "Content-Security-Policy" => "frame-ancestors http:" }, :frame],
      "frame-ancestors *"                                     => [{ "Content-Security-Policy" => "frame-ancestors *" }, :frame],
      "frame-ancestors on another host"                       => [{ "Content-Security-Policy" => "frame-ancestors https://*.example.com" }, :window],
      "a policy without frame-ancestors"                      => [{ "Content-Security-Policy" => "default-src 'none'" }, :frame],
      "two policies, the second refusing"                     => [{ "Content-Security-Policy" => ["frame-ancestors *", "frame-ancestors 'none'"] }, :window],
      "frame-ancestors allowing it but X-Frame-Options: DENY" => [{ "Content-Security-Policy" => "frame-ancestors *", "X-Frame-Options" => "DENY" }, :window]
    }.each do |what, (headers, verdict)|
      it "is #{verdict} for #{what}" do
        expect(described_class.verdict(headers, origin:)).to eq(verdict)
      end
    end

    it "matches a wildcard host" do
      headers = { "Content-Security-Policy" => "frame-ancestors http://*.example.com:8080" }
      expect(described_class.verdict(headers, origin: "http://board.example.com:8080")).to eq(:frame)
    end
  end

  describe ".check" do
    def serving(header)
      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new do
        client = server.accept
        client.readpartial(4096)
        client.write("HTTP/1.1 200 OK\r\n#{header}Content-Length: 2\r\nConnection: close\r\n\r\nok")
        client.close
      end
      yield "http://127.0.0.1:#{server.addr[1]}/"
    ensure
      server&.close
      thread&.kill
    end

    it "reads the real response's headers" do
      serving("X-Frame-Options: DENY\r\n") { |url| expect(described_class.check(url, origin:)).to eq(:window) }
    end

    it "frames an app that sends none" do
      serving("") { |url| expect(described_class.check(url, origin:)).to eq(:frame) }
    end

    it "opens a window for an app it cannot ask" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      server.close
      expect(described_class.check("http://127.0.0.1:#{port}/", origin:)).to eq(:window)
    end
  end
end

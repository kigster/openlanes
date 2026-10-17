# frozen_string_literal: true

require "socket"

# Against real sockets on 127.0.0.1: a fake listener would test the fake.
RSpec.describe OpenLanes::Apps::Probe do
  # A one-thread HTTP server answering every request with +code+.
  def serving(code)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      loop do
        client = server.accept
        # The probe's bare connect sends nothing and hangs up.
        client.write("HTTP/1.1 #{code} X\r\nContent-Length: 0\r\nConnection: close\r\n\r\n") if client.readpartial(4096)
      rescue EOFError
        next
      rescue IOError, SystemCallError
        break
      ensure
        client&.close
      end
    end
    yield server.addr[1]
  ensure
    server&.close
    thread&.kill
  end

  def closed_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1].tap { server.close }
  end

  it "is ready on a TCP connect when no path is asked for" do
    server = TCPServer.new("127.0.0.1", 0)
    expect(described_class.ready?(server.addr[1])).to be(true)
  ensure
    server&.close
  end

  it "is not ready when nothing listens" do
    expect(described_class.ready?(closed_port)).to be(false)
  end

  # What a refused connect looks like behind Little Snitch: Socket.tcp hands
  # back a socket, and only asking it for its peer shows nothing is there.
  it "is not listening when the socket it was handed has no peer" do
    peerless = instance_double(Socket)
    allow(peerless).to receive(:remote_address).and_raise(Errno::EINVAL)
    allow(Socket).to receive(:tcp).and_yield(peerless)

    aggregate_failures do
      expect(described_class.listening?(11_100)).to be(false)
      expect(OpenLanes::Apps::Ports.answering?(11_100)).to be(false)
    end
  end

  { 200 => true, 302 => true, 404 => false, 503 => false }.each do |code, ready|
    it "is #{"not " unless ready}ready when the path answers #{code}" do
      serving(code) { |port| expect(described_class.ready?(port, path: "/up")).to be(ready) }
    end
  end

  it "answers 0 for a path on a port that refuses" do
    expect(described_class.status(closed_port, "/")).to eq(0)
  end
end

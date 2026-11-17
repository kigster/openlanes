# frozen_string_literal: true

require "socket"

RSpec.describe OpenLanes::Web::Ports do
  # A port the OS hands out, so the spec never touches 11000.
  def held
    server = TCPServer.new("127.0.0.1", 0)
    [server, server.addr[1]]
  end

  it "answers the port asked for when nothing listens there" do
    server, port = held
    server.close
    expect(described_class.first_free(port)).to eq(port)
  end

  it "steps past a taken port" do
    server, port = held
    expect(described_class.first_free(port.to_s)).to be > port
  ensure
    server&.close
  end

  it "answers nil when every port tried is taken" do
    server, port = held
    expect(described_class.first_free(port, tried: 1)).to be_nil
  ensure
    server&.close
  end
end

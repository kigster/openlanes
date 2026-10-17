# frozen_string_literal: true

RSpec.describe OpenLanes::Web::Listen do
  let(:addresses) { %w[127.0.0.1 ::1 192.168.1.20 fd00::7] }

  describe ".parse" do
    it "is loopback when nothing is given" do
      expect([nil, "", " , "].map { described_class.parse(it).ips }).to all(eq(%w[127.0.0.1]))
    end

    it "splits on commas, trims and drops repeats" do
      expect(described_class.parse(" 127.0.0.1,192.168.1.20 ,127.0.0.1").ips).to eq(%w[127.0.0.1 192.168.1.20])
    end

    it "names what is not an address" do
      expect { described_class.parse("127.0.0.1,box.local") }
        .to raise_error(described_class::Invalid, '"box.local" is not an IP address')
    end
  end

  describe "#public?" do
    it "is true once anything past loopback is listened on" do
      expect(%w[127.0.0.1 ::1 127.0.0.1,0.0.0.0 192.168.1.20].map { described_class.parse(it).public? })
        .to eq([false, false, true, true])
    end
  end

  describe "#browse_url" do
    it "opens loopback where a wildcard or loopback is listened on, else the first address" do
      expect(%w[0.0.0.0 :: 192.168.1.20,127.0.0.1 192.168.1.20].map { described_class.parse(it).browse_url(11_000) })
        .to eq(%w[http://127.0.0.1:11000 http://[::1]:11000 http://127.0.0.1:11000 http://192.168.1.20:11000])
    end
  end

  describe "#urls" do
    it "spells 0.0.0.0 out as this machine's IPv4 addresses, and :: as all of them, being dual-stack" do
      expect([described_class.parse("0.0.0.0").urls(80, addresses:), described_class.parse("::").urls(80, addresses:)])
        .to eq([%w[http://127.0.0.1:80 http://192.168.1.20:80],
                %w[http://127.0.0.1:80 http://[::1]:80 http://192.168.1.20:80 http://[fd00::7]:80]])
    end
  end

  describe "#permitted_hosts" do
    it "adds nothing for loopback, which the app always answers" do
      expect(described_class.parse("127.0.0.1").permitted_hosts(addresses:, hostname: "box.local")).to eq([])
    end

    it "adds the addresses listened on and this machine's name" do
      hosts = described_class.parse("0.0.0.0").permitted_hosts(addresses:, hostname: "box.local")
      expect(hosts).to eq(["box.local", "box", IPAddr.new("127.0.0.1"), IPAddr.new("192.168.1.20")])
    end

    it "permits IPv4 Host headers under ::, which answers IPv4 clients too" do
      hosts = described_class.parse("::").permitted_hosts(addresses:, hostname: "box")
      expect(hosts).to eq(["box", *%w[127.0.0.1 ::1 192.168.1.20 fd00::7].map { IPAddr.new(it) }])
    end
  end

  describe ".addresses" do
    it "lists this machine's addresses, loopback first, with no link-local IPv6" do
      list = described_class.addresses
      expect([list.first, list.none? { it.start_with?("fe80") }]).to eq(["127.0.0.1", true]).or eq(["::1", true])
    end
  end
end

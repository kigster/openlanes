# frozen_string_literal: true

RSpec.describe OpenLanes::Web do
  describe ".display?" do
    let(:mac) { "darwin25" }
    let(:linux) { "linux-gnu" }

    it "is true at a Mac's terminal" do
      expect(described_class.display?(env: {}, tty: true, os: mac)).to be(true)
    end

    it "is false without a terminal" do
      expect(described_class.display?(env: {}, tty: false, os: mac)).to be(false)
    end

    it "is false under CI" do
      expect(described_class.display?(env: { "CI" => "true" }, tty: true, os: mac)).to be(false)
    end

    it "is false over SSH" do
      expect(described_class.display?(env: { "SSH_CONNECTION" => "1.2.3.4 5 6.7.8.9 22" }, tty: true, os: mac)).to be(false)
    end

    it "is false on Linux without a display" do
      expect(described_class.display?(env: {}, tty: true, os: linux)).to be(false)
    end

    it "is true on Linux with Wayland" do
      expect(described_class.display?(env: { "WAYLAND_DISPLAY" => "wayland-0" }, tty: true, os: linux)).to be(true)
    end
  end

  describe ".open" do
    before do
      require "launchy"
      allow(Launchy).to receive(:open)
    end

    it "opens the page when there is a display" do
      described_class.open("http://127.0.0.1:11000", display: true)
      expect(Launchy).to have_received(:open).with("http://127.0.0.1:11000")
    end

    it "says it did" do
      expect(described_class.open("http://127.0.0.1:11000", display: true)).to be(true)
    end

    it "does nothing without one" do
      described_class.open("http://127.0.0.1:11000", display: false)
      expect(Launchy).not_to have_received(:open)
    end

    it "answers false when no browser can be found" do
      allow(Launchy).to receive(:open).and_raise(Launchy::CommandNotFoundError, "no browser")
      expect(described_class.open("http://127.0.0.1:11000", display: true)).to be(false)
    end
  end

  describe ".launcher" do
    it "builds one" do
      expect(described_class.launcher(root: "/r", plans_dir: "/r/.plans", port: 1, redis_url: "x"))
        .to be_a(OpenLanes::Web::Launcher)
    end
  end

  describe OpenLanes::Web::Stores do
    subject(:stores) { described_class.new { made << Object.new; made.last } }

    let(:made) { [] }

    it "gives each thread a store of its own, and the same one each time" do
      mine = [stores.current, stores.current]
      theirs = Thread.new { stores.current }.value
      expect([mine.uniq.size, theirs.equal?(mine.first)]).to eq([1, false])
    end

    it "closes every store it made" do
      store = instance_double(OpenLanes::Live::Store, close: nil)
      shared = described_class.shared(store)
      shared.current
      shared.close
      expect(store).to have_received(:close)
    end
  end
end

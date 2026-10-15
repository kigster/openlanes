# frozen_string_literal: true

require "socket"

RSpec.describe OpenLanes::Apps::Ports do
  let(:dir) { Dir.mktmpdir("openlanes-ports") }
  let(:path) { File.join(dir, "state", "ports.json") }
  let(:everything_free) { ->(_) { true } }

  after { FileUtils.rm_rf(dir) }

  def registry(**) = described_class.new(path:, free: everything_free, **)

  describe "#reserve" do
    it "hands out the lowest free ports from 11100 up" do
      ports = registry
      expect([ports.reserve(root: "/a", plan: "012.00", process: "api"), ports.reserve(root: "/a", plan: "012.00", process: "web")])
        .to eq([11_100, 11_101])
    end

    it "records who holds each port" do
      registry(owner: Process.pid).reserve(root: "/a", plan: "012.00", process: "api")
      expect(registry.entries[11_100]).to include("owner" => Process.pid, "root" => "/a", "plan" => "012.00", "process" => "api")
    end

    it "gives two checkouts sharing the machine's file disjoint ports" do
      one = registry.reserve(root: "/work/main", plan: "012.00", process: "web")
      two = registry.reserve(root: "/work/worktrees/012.00-app", plan: "012.00", process: "web")
      expect([one, two]).to eq([11_100, 11_101])
    end

    it "skips a port something outside the registry is listening on" do
      server = TCPServer.new("127.0.0.1", 0)
      held = server.addr[1]
      ports = described_class.new(path:, floor: held, ceiling: held + 20)
      expect(ports.reserve(root: "/a", plan: "012.00", process: "web")).to be > held
    ensure
      server&.close
    end

    it "reclaims a port whose owner is no longer running" do
      dead = registry(owner: 999_999, alive: ->(pid) { pid != 999_999 })
      dead.reserve(root: "/a", plan: "012.00", process: "web")
      expect(registry(alive: ->(pid) { pid != 999_999 }).reserve(root: "/b", plan: "014.00", process: "web")).to eq(11_100)
    end

    it "says so when every port is taken" do
      ports = registry(floor: 11_100, ceiling: 11_101)
      2.times { ports.reserve(root: "/a", plan: "012.00", process: "p") }
      expect { ports.reserve(root: "/a", plan: "012.00", process: "p") }
        .to raise_error(described_class::Exhausted, /from 11100 to 11101/)
    end

    it "treats a file somebody broke by hand as empty" do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "{oops")
      expect(registry.reserve(root: "/a", plan: "012.00", process: "web")).to eq(11_100)
    end
  end

  describe "#release and #release_owner" do
    it "frees one port" do
      ports = registry
      port = ports.reserve(root: "/a", plan: "012.00", process: "web")
      ports.release(port)
      expect(ports.entries).to be_empty
    end

    it "frees every port one owner held, and only those" do
      mine = registry(owner: Process.pid)
      theirs = registry(owner: Process.ppid)
      2.times { mine.reserve(root: "/a", plan: "012.00", process: "p") }
      theirs.reserve(root: "/b", plan: "014.00", process: "p")
      expect(mine.release_owner).to eq([11_100, 11_101])
      expect(mine.entries.keys).to eq([11_102])
    end
  end

  describe ".default_path" do
    it "is $OPENLANES_PORTS_FILE when set" do
      expect(described_class.default_path("OPENLANES_PORTS_FILE" => "/tmp/p.json")).to eq("/tmp/p.json")
    end

    it "is under XDG_STATE_HOME, else ~/.local/state" do
      expect([described_class.default_path("XDG_STATE_HOME" => "/s"), described_class.default_path({})])
        .to eq(["/s/openlanes/ports.json", File.expand_path("~/.local/state/openlanes/ports.json")])
    end
  end

  describe ".free? and .alive?" do
    it "answers for a real listener and a real process" do
      server = TCPServer.new("127.0.0.1", 0)
      expect([described_class.free?(server.addr[1]), described_class.alive?(Process.pid), described_class.alive?(2**31)])
        .to eq([false, true, false])
    ensure
      server&.close
    end
  end
end

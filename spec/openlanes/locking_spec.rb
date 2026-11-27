# frozen_string_literal: true

RSpec.describe OpenLanes::Locking do
  after do
    described_class.adapter = nil
    described_class.redis_url = nil
  end

  it "locks on the engine's Redis, and on the configured one until a run names its own" do
    configured = described_class.redis_url
    described_class.redis_url = "redis://locks.test:6379/3"

    expect([configured, described_class.redis_url]).to eq([OpenLanes::Live.redis_url, "redis://locks.test:6379/3"])
  end

  it "signs as this process, and hands an agent that id as its parent" do
    expect(described_class.child_environment)
      .to eq("AGENT_PARENT_ID" => "openlanes@#{Socket.gethostname}:#{Process.pid}", "AGENT_LOCK_BACKEND" => "redis")
  end

  it "makes one adapter for every thread, and takes another in its place" do
    adapters = Array.new(8) { Thread.new { described_class.adapter } }.map(&:value)
    other = Object.new
    described_class.adapter = other

    expect([adapters.uniq.size, adapters.first.class, described_class.adapter]).to eq([1, OpenLanes::Locking::Distributed, other])
  end

  # The register is asked in process, through agent-lock's Ruby API on
  # Redis. A forked `alock` chooses its own backend, the file store when
  # Redis does not answer, so no code here may run one.
  it "runs no alock command anywhere" do
    lib = File.expand_path("../../lib/openlanes", __dir__)
    # Code, not comments, that hands alock to a process: "alock" as its own
    # argument (whatever comes before it, an env hash included), %w[alock
    # ...], a backtick command, or "alock <subcommand> ..." as one string.
    # Log lines and prompt text only name alock, and are not runs.
    subcommand = /["']alock\s+(acquire|release(-all)?|list|break|resume|note|whoami)(["']|\s+["'<-])/
    runner = Regexp.union(/["']alock["']/, /%[wi][\[({]\s*alock\b/, /(^|[=(,]\s*)`alock\s/, subcommand)
    runs = ->(file) { File.readlines(file).any? { |line| !line.lstrip.start_with?("#") && line.match?(runner) } }
    runners = Dir.glob("#{lib}/**/*.rb").select(&runs)

    expect(runners.map { it.delete_prefix("#{lib}/") }).to eq([])
  end

  # The engine depends on execution, so execution must not depend on the
  # engine: the holder id living in `Engine` once closed that loop.
  it "keeps execution from reaching up into the engine" do
    lib = File.expand_path("../../lib/openlanes/execution", __dir__)
    upward = Dir.glob("#{lib}/**/*.rb").select do |file|
      File.readlines(file).any? { |line| !line.lstrip.start_with?("#") && line.match?(/\bEngine(::|\.)/) }
    end

    expect(upward).to be_empty
  end
end

# frozen_string_literal: true

RSpec.describe OpenLanes::Locking do
  after { described_class.adapter = nil }

  it "signs as this process, and hands an agent that id as its parent" do
    expect(described_class.child_environment)
      .to eq("AGENT_PARENT_ID" => "openlanes@#{Socket.gethostname}:#{Process.pid}")
  end

  it "makes one adapter for every thread, and takes another in its place" do
    adapters = Array.new(8) { Thread.new { described_class.adapter } }.map(&:value)
    other = Object.new
    described_class.adapter = other

    expect([adapters.uniq.size, adapters.first.class, described_class.adapter]).to eq([1, OpenLanes::Locking::Shell, other])
  end

  # Every call to alock goes through one adapter, so a Ruby adapter for
  # agent-lock can replace it with no caller changing.
  it "is the only code that runs alock" do
    lib = File.expand_path("../../lib/openlanes", __dir__)
    # Code, not comments, that hands alock to a process: "alock" as its own
    # argument (whatever comes before it, an env hash included), %w[alock
    # ...], a backtick command, or "alock <subcommand> ..." as one string.
    # Log lines and prompt text only name alock, and are not runs.
    subcommand = /["']alock\s+(acquire|release(-all)?|list|break|resume|note|whoami)(["']|\s+["'<-])/
    runner = Regexp.union(/["']alock["']/, /%[wi][\[({]\s*alock\b/, /(^|[=(,]\s*)`alock\s/, subcommand)
    runs = ->(file) { File.readlines(file).any? { |line| !line.lstrip.start_with?("#") && line.match?(runner) } }
    runners = Dir.glob("#{lib}/**/*.rb").select(&runs)

    expect(runners.map { it.delete_prefix("#{lib}/") }).to eq(["locking/shell.rb"])
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

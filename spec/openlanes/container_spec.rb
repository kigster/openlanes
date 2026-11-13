# frozen_string_literal: true

RSpec.describe OpenLanes::Container do
  describe "components" do
    it "keys a class by its path and builds it from the constant Zeitwerk expects there" do
      expect(described_class["engine.upkeep.owed"]).to be_a(OpenLanes::Engine::Upkeep::Owed)
    end

    it "keeps a collapsed directory in the key while the constant skips it" do
      expect(described_class["support.clock"]).to be(OpenLanes::Clock)
    end

    it "follows Zeitwerk's acronyms rather than inflecting the key again" do
      expect(described_class["vcs.github"]).to be_a(OpenLanes::Vcs::GitHub)
    end

    it "hands out a facade module as itself" do
      expect(described_class["engine.upkeep"]).to be(OpenLanes::Engine::Upkeep)
    end

    it "registers no file Zeitwerk ignores, nor the wiring itself" do
      expect(described_class.keys).not_to include("linear.mapping", "container", "deps", "providers.github")
    end
  end

  describe "providers" do
    it "hands out the outside world as the code builds it by hand" do
      aggregate_failures do
        expect(described_class["github"]).to be_a(OpenLanes::Vcs::GitHub)
        expect(described_class["clock"]).to be(OpenLanes::Clock::System)
        expect(described_class["process"]).to be(OpenLanes::Spawner::System)
        expect(described_class["logger"]).to be_a(SemanticLogger::Logger)
      end
    end

    it "authenticates Linear from the environment" do
      allow(OpenLanes::Linear::API).to receive(:token_from_env).and_return("lin_api_example")

      expect(described_class["linear"]).to be_a(OpenLanes::Linear::API)
    end

    it "puts the event bus over the process's Redis" do
      store = OpenLanes::Live.memory_store
      described_class.stub("redis", store)

      expect(described_class["event_bus"]).to have_attributes(class: OpenLanes::Live::EventBus::MemoryBus, store:)
    end

    # A memoized bus kept the first example's store, so the second one's
    # events landed in a stream nobody read.
    it "builds the bus over whichever Redis is stubbed now" do
      first = OpenLanes::Live.memory_store
      second = OpenLanes::Live.memory_store

      described_class.stub("redis", first) { described_class["event_bus"] }
      described_class.stub("redis", second) do
        expect(described_class["event_bus"].store).to be(second)
      end
    end

    it "registers Redis and the event bus without connecting" do
      expect(described_class.keys).to include("redis", "event_bus")
    end

    # Two threads resolving an unstarted provider together race dry-system's
    # unlocked first start, so the ones threads share are started at boot.
    # The list is a fact about the providers and lives beside them, not in
    # the load file.
    it "starts the eager providers at boot, and only providers that exist" do
      aggregate_failures do
        expect(described_class::EAGER).to eq(%w[clock process logger])
        expect(described_class::EAGER.map { described_class.providers[it.to_sym].started? }).to all(be(true))
        expect(Dir[File.expand_path("../../lib/openlanes/providers/*.rb", __dir__)].map { File.basename(it, ".rb") })
          .to include(*described_class::EAGER)
      end
    end
  end

  describe "the Redis provider" do
    # A source of its own, so starting and stopping it leaves the suite's
    # container, and its memoized connection, alone.
    let(:source) do
      source_class = described_class.providers[:redis].source.class
      source_class.new(provider_container: Dry::Core::Container.new, target_container: described_class)
    end
    let(:connection) { instance_double(OpenLanes::Live::Store, close: nil) }

    before { allow(OpenLanes::Live).to receive(:connect).and_return(connection) }

    it "closes the connection it made when stopped" do
      source.start
      source.container["redis"]
      source.stop

      expect(connection).to have_received(:close)
    end

    it "stops without connecting when Redis was never resolved" do
      source.start
      source.stop

      expect(OpenLanes::Live).not_to have_received(:connect)
    end
  end

  describe ".stub" do
    it "swaps a component for the block, then puts it back" do
      fake = OpenLanes::Clock::Fake.new

      described_class.stub("clock", fake) { expect(described_class["clock"]).to be(fake) }

      expect(described_class["clock"]).to be(OpenLanes::Clock::System)
    end
  end

  describe OpenLanes::Deps do
    let(:injected) do
      Class.new do
        include OpenLanes::Deps["github", "clock"]
      end
    end

    it "defaults each keyword to the container's, stubs included" do
      fake = OpenLanes::Clock::Fake.new
      described_class
      OpenLanes::Container.stub("clock", fake)

      expect(injected.new.clock).to be(fake)
    end

    it "still takes what a caller passes" do
      expect(injected.new(clock: :given).clock).to eq(:given)
    end
  end

  describe "the keys this wiring leaves behind" do
    it "keeps a collapsed cli/<command>/ directory in the key: cli/create/create.rb is cli.create.create" do
      expect(described_class["cli.create.create"]).to be_a(OpenLanes::CLI::Create)
    end

    it "has a provider file for exactly the seven provider keys" do
      providers = Dir[File.expand_path("../../lib/openlanes/providers/*.rb", __dir__)].map { File.basename(it, ".rb") }

      expect(providers).to match_array(%w[clock event_bus github linear logger process redis])
    end

    it "resolves each provider key" do
      allow(OpenLanes::Linear::API).to receive(:token_from_env).and_return("lin_api_example")
      described_class.stub("redis", OpenLanes::Live.memory_store)

      %w[clock event_bus github linear logger process redis].each do |key|
        expect(described_class[key]).not_to be_nil, "#{key} resolved to nil"
      end
    end

    {
      "claude" => OpenLanes::Adapters::Claude,
      "codex"  => OpenLanes::Adapters::Codex,
      "pi"     => OpenLanes::Adapters::Pi,
      "grok"   => OpenLanes::Adapters::Grok,
      "gemini" => OpenLanes::Adapters::Gemini
    }.each do |name, klass|
      it "resolves adapters.#{name} to its adapter" do
        expect(described_class["adapters.#{name}"]).to be_a(klass)
      end
    end
  end
end

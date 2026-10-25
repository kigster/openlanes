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
      described_class.stub("redis", store) do
        expect(OpenLanes::Live::EventBus.for(described_class["redis"])).to be_a(OpenLanes::Live::EventBus::MemoryBus)
      end
    end

    it "registers Redis and the event bus without connecting" do
      expect(described_class.keys).to include("redis", "event_bus")
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
end

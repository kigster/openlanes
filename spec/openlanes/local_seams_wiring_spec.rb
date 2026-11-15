# frozen_string_literal: true

# The `clock`, `process` and `logger` keys reach every class that used to
# name {OpenLanes::Clock::System}, {OpenLanes::Spawner::System} or
# {OpenLanes::Log.logger} as a default: stubbing the key is enough to hold a
# spec's time still or keep it from starting a process, with no constructor
# argument threaded through.
RSpec.describe "the local seams through the container" do
  let(:clock) { OpenLanes::Clock::Fake.new(now: Time.utc(2026, 11, 13, 12, 0, 0)) }
  let(:spawner) { OpenLanes::Spawner::Fake.new }

  before do
    OpenLanes::Container.stub("clock", clock)
    OpenLanes::Container.stub("process", spawner)
  end

  it "starts the pure providers at boot, so no thread is first to resolve one" do
    expect(%i[clock process logger].map { OpenLanes::Container.providers[it].started? }).to all(be(true))
  end

  describe "the clock" do
    it "reaches Supervision::Crashes" do
      expect(OpenLanes::Supervision::Crashes.new.instance_variable_get(:@clock)).to be(clock)
    end

    it "reaches Supervision::Host" do
      expect(OpenLanes::Supervision::Host.new.clock).to be(clock)
    end

    it "times Engine::Narrator's lines" do
      expect(OpenLanes::Engine::Narrator.new.instance_variable_get(:@clock).call).to eq(clock.now)
    end

    it "times Engine::Extensions' answers" do
      expect(OpenLanes::Engine::Extensions.new(stay: true).instance_variable_get(:@now).call).to eq(clock.now)
    end
  end

  describe "the process seam" do
    it "reaches Supervision::Host" do
      expect(OpenLanes::Supervision::Host.new.spawner).to be(spawner)
    end

    it "reaches Execution::AgentProcess::Starter" do
      expect(OpenLanes::Execution::AgentProcess::Starter.new(dir: "/tmp", root: "/tmp").spawner).to be(spawner)
    end

    it "still takes a spawner a caller passes in" do
      own = OpenLanes::Spawner::Fake.new

      expect(OpenLanes::Execution::AgentProcess::Starter.new(dir: "/tmp", root: "/tmp", spawner: own).spawner).to be(own)
    end
  end

  describe "the logger" do
    it "is what Web::RequestLog writes to when built without one" do
      logger = instance_spy(SemanticLogger::Logger)
      OpenLanes::Container.stub("logger", logger)
      app = OpenLanes::Web::RequestLog.new(->(_env) { [200, {}, []] })

      app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => "/api/plans" })

      expect(logger).to have_received(:info)
    end
  end
end

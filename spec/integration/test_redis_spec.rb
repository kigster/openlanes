# frozen_string_literal: true

RSpec.describe TestRedis do
  describe ".scrub!" do
    it "drops what the shell exported and points REDIS_URL where nothing answers" do
      env = { "REDIS_URL" => "redis://shared.example.net:6379/0", "OPENLANES_REDIS_URL" => "redis://run-host/2" }
      described_class.scrub!(env)
      expect(env).to eq("REDIS_URL" => described_class::UNREACHABLE)
    end

    it "left this suite's own environment scrubbed" do
      expect([ENV.fetch("REDIS_URL", nil), ENV.fetch("OPENLANES_REDIS_URL", nil)])
        .to eq([described_class::UNREACHABLE, nil])
    end
  end

  describe ".url" do
    it "names the database on the local Redis" do
      expect([described_class.url(12, env: {}),
              described_class.url(10, env: { "OPENLANES_TEST_REDIS_URL" => "redis://127.0.0.1:6380/15" })])
        .to eq(%w[redis://localhost:6379/12 redis://127.0.0.1:6380/10])
    end

    it "refuses a Redis on another host" do
      expect { described_class.url(15, env: { "OPENLANES_TEST_REDIS_URL" => "redis://cache.example.net:6379/15" }) }
        .to raise_error(ArgumentError, /refusing cache\.example\.net/)
    end
  end

  describe ".exclusively" do
    let(:env) { { "OPENLANES_TEST_REDIS_URL" => "redis://localhost:#{40_000 + (Process.pid % 20_000)}/15" } }
    let(:path) { described_class.lock_path(env:) }

    def held_elsewhere?(path)
      script = "f = File.open(ARGV[0], File::RDWR | File::CREAT); exit(f.flock(File::LOCK_EX | File::LOCK_NB) ? 1 : 0)"
      system(RbConfig.ruby, "-e", script, path)
    end

    after { FileUtils.rm_f(path) }

    it "keeps another process out while the block runs, and nests without waiting on itself" do
      seen = described_class.exclusively(env:) do
        described_class.exclusively(env:) { [held_elsewhere?(path), :inner] }
      end
      expect([seen, held_elsewhere?(path)]).to eq([[true, :inner], false])
    end

    it "keys the lock by server, so every database on it shares one" do
      expect(path).to end_with("openlanes-test-redis-localhost-#{40_000 + (Process.pid % 20_000)}.lock")
    end
  end
end

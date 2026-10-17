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

    it "keeps a unix socket's path and carries the database as ?db=" do
      env = { "OPENLANES_TEST_REDIS_URL" => "unix:///tmp/redis.sock" }
      expect(described_class.url(12, env:)).to eq("unix:///tmp/redis.sock?db=12")
    end

    it "refuses a Redis on another host" do
      expect { described_class.url(15, env: { "OPENLANES_TEST_REDIS_URL" => "redis://cache.example.net:6379/15" }) }
        .to raise_error(ArgumentError, /refusing cache\.example\.net/)
    end
  end

  describe ".database" do
    it "reads the database from a path or from a unix URL's db parameter" do
      expect(%w[redis://localhost:6379/12 redis://localhost:6379 unix:///tmp/r.sock?db=11 unix:///tmp/r.sock]
        .map { described_class.database(it) }).to eq(["12", "", "11", nil])
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
      expect(path).to eq("/tmp/openlanes-test-redis-loopback-#{40_000 + (Process.pid % 20_000)}.lock")
    end

    it "gives loopback aliases and the default port one lock" do
      paths = ["redis://localhost:6379/15", "redis://127.0.0.1:6379/3", "redis://localhost/15"]
              .map { described_class.lock_path(env: { "OPENLANES_TEST_REDIS_URL" => it }) }
      expect(paths.uniq.size).to eq(1)
    end

    it "keys a unix socket's lock on the socket, not on the database" do
      paths = %w[/tmp/a.sock /tmp/b.sock].map do |sock|
        described_class.lock_path(env: { "OPENLANES_TEST_REDIS_URL" => "unix://#{sock}" })
      end
      expect(paths).to eq(%w[/tmp/openlanes-test-redis-_tmp_a.sock.lock /tmp/openlanes-test-redis-_tmp_b.sock.lock])
    end

    it "ignores $TMPDIR and honours OPENLANES_TEST_LOCK_DIR" do
      custom = env.merge("OPENLANES_TEST_LOCK_DIR" => "/var/lock-here")
      expect(described_class.lock_path(env: custom)).to start_with("/var/lock-here/")
    end

    it "stays usable after an acquisition fails" do
      remote = { "OPENLANES_TEST_REDIS_URL" => "redis://cache.example.net:6379/15" }
      expect { described_class.exclusively(env: remote) { :never } }.to raise_error(ArgumentError)
      seen = described_class.exclusively(env:) { held_elsewhere?(path) }
      expect(seen).to be(true)
    end
  end
end

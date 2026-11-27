# frozen_string_literal: true

# agent-lock's Ruby API, in this process, on the local Redis: the gem's own
# code takes and refuses every lock, and nothing about it is mocked.
#
# Database 9 is these examples' alone. On 15, an integration run's
# ControlRoomProcess#stop_all flushed it mid-claim, deleting agent-lock's
# mutex key, and the claim failed as a lost lease.
RSpec.describe OpenLanes::Locking::Distributed, :redis do
  subject(:adapter) { described_class.new(url: -> { url }) }

  let(:url) { TestRedis.url(9) }
  let(:redis) { Agent::Lock::Facade.new(strategies: %w[redis], redis_url: url) }
  let(:root) { File.realpath(Dir.mktmpdir("distributed")) }
  let(:plans) { File.join(root, ".plans") }
  let(:scope) { "003.00━━🟡━━❯tax-rule-dsl/**" }

  before do
    Redis.new(url:).then { it.flushdb && it.close }
    system("git", "init", "-q", root, exception: true)
    FileUtils.mkdir_p(File.join(plans, "003.00━━🟡━━❯tax-rule-dsl"))
  end

  after { FileUtils.rm_rf(root) }

  it "takes a lock, refuses it to another holder, lists it, and releases it" do
    outcomes = [adapter.acquire(scope, "building", dir: plans, as: "openlanes@one"),
                adapter.acquire(scope, "also", dir: plans, as: "openlanes@two")]
    listed = adapter.list(root)
    released = adapter.release(scope, dir: plans, as: "openlanes@one")

    expect([outcomes.map(&:status), outcomes.last.message, listed, released.status, adapter.list(root)])
      .to eq([%i[done refused], "REFUSED, do not write here",
              [OpenLanes::Locking::Lock.new(agent: "openlanes@one", scope: ".plans/#{scope}", tree: root, intent: "building")],
              :done, []])
  end

  it "says acquiring a lock it already holds is done" do
    adapter.acquire(scope, "building", dir: plans, as: "openlanes@one")

    expect(adapter.acquire(scope, "again", dir: plans, as: "openlanes@one")).to be_done
  end

  it "refuses to release what nobody holds, and what somebody else holds" do
    adapter.acquire(scope, "building", dir: plans, as: "openlanes@one")

    expect([adapter.release("other/**", dir: plans, as: "openlanes@one"),
            adapter.release(scope, dir: plans, as: "openlanes@two")].map(&:status))
      .to eq(%i[refused refused])
  end

  it "keeps working AgentLocks, unchanged, through the process-wide adapter" do
    OpenLanes::Locking.adapter = adapter
    folder = File.join(plans, "003.00━━🟡━━❯tax-rule-dsl")
    one = OpenLanes::Engine::AgentLocks.new(root:, id: "openlanes@one")
    two = OpenLanes::Engine::AgentLocks.new(root:, id: "openlanes@two")

    expect([one.acquire(folder, "x"), two.acquire(folder, "y"), two.held_elsewhere(folder)&.agent])
      .to eq([true, false, "openlanes@one"])
  ensure
    OpenLanes::Locking.adapter = nil
  end

  it "fails each call, and asks Redis again on the next, while Redis does not answer" do
    asked = 0
    down = described_class.new(build: ->(_) { (asked += 1) && raise(Agent::Lock::RedisUnavailableError, "Redis did not answer") })

    status = down.acquire(scope, "x", dir: plans, as: "me").status

    expect { down.list(root) }.to raise_error(OpenLanes::Locking::Unreadable, /did not answer/)
    expect([status, asked]).to eq([:failed, 2])
  end

  it "fails one call, and keeps the adapter on, when the store does not answer" do
    broken = Class.new { def acquire(*, **) = raise(Redis::CannotConnectError, "Connection refused\nsecond line") }.new
    down = described_class.new(build: ->(_) { broken })

    expect(down.acquire(scope, "x", dir: plans, as: "me")).to eq(OpenLanes::Locking::Outcome.new(status: :failed, message: "Connection refused"))
  end

  it "says a listing that failed is unreadable" do
    broken = Class.new { def list(**) = raise(Agent::Lock::Store::Mismatch, "this tree's locks live in redis") }.new

    expect { described_class.new(build: ->(_) { broken }).list(root) }
      .to raise_error(OpenLanes::Locking::Unreadable, /live in redis/)
  end

  # The contract's lifetime rule: a lock ends with the engine. agent-lock
  # reaps a lock on this host when the pid in its record is gone, so that
  # pid must be this process, not the terminal above it.
  it "signs every lock with this process, so the lock ends with the engine" do
    adapter.acquire(scope, "building", dir: plans, as: "openlanes@one")

    expect(redis.list(dir: root).records.map(&:pid)).to eq([Process.pid])
  end

  # The split this closes: an engine on `--redis-url` whose locks went to
  # `$REDIS_URL`, where no other engine on its Redis could see them.
  it "locks on the Redis the engine runs on, one facade per URL, built once" do
    built = []
    urls = %w[redis://one redis://one redis://two]
    several = described_class.new(build: ->(to) { built << to and redis }, url: -> { urls.shift })

    3.times { several.list(root) }

    expect(built).to eq(%w[redis://one redis://two])
  end

  it "is the adapter openlanes uses unless told otherwise" do
    OpenLanes::Locking.adapter = nil

    expect(OpenLanes::Locking.adapter).to be_a(described_class)
  ensure
    OpenLanes::Locking.adapter = nil
  end
end

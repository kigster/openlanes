# frozen_string_literal: true

# "No caller changes": AgentLocks runs on any adapter that keeps the
# Locking::Adapter contract. This one keeps the register in memory, the way
# an adapter over agent-lock's Ruby API would keep it in the gem.
RSpec.describe "a locking adapter other than Shell" do
  let(:memory) do
    Class.new do
      include OpenLanes::Locking::Adapter

      def initialize = (@locks = {}) && (@mutex = Mutex.new)

      def list(root) = @mutex.synchronize { @locks.map { |(dir, scope), agent| OpenLanes::Locking::Lock.new(agent:, scope: File.join(dir.delete_prefix(root).delete_prefix("/"), scope), tree: root, intent: nil) } }

      def acquire(scope, _intent, dir:, as:)
        @mutex.synchronize do
          holder = @locks[[dir, scope]]
          next OpenLanes::Locking::Outcome.new(status: :refused, message: "HELD by #{holder}") if holder && holder != as

          @locks[[dir, scope]] = as
          OpenLanes::Locking::Outcome.new(status: :done)
        end
      end

      def release(scope, dir:, as:)
        @mutex.synchronize do
          next OpenLanes::Locking::Outcome.new(status: :refused) unless @locks[[dir, scope]] == as

          @locks.delete([dir, scope])
          OpenLanes::Locking::Outcome.new(status: :done)
        end
      end
    end.new
  end
  let(:root) { File.realpath(Dir.mktmpdir("adapter-contract")) }
  let(:folder) { File.join(root, ".plans", "003.00━━🟡━━❯tax-rule-dsl") }

  before { FileUtils.mkdir_p(folder) }

  after do
    OpenLanes::Locking.adapter = nil
    FileUtils.rm_rf(root)
  end

  def engine(id, **) = OpenLanes::Engine::AgentLocks.new(root:, id:, **)

  it "claims, refuses a second engine, sees the holder and releases, with no change to AgentLocks" do
    one = engine("openlanes@one", adapter: memory)
    two = engine("openlanes@two", adapter: memory)

    expect([one.acquire(folder, "x"), two.acquire(folder, "y"), two.held_elsewhere(folder)&.agent,
            one.release(folder), two.acquire(folder, "y")])
      .to eq([true, false, "openlanes@one", true, true])
  end

  it "reaches an adapter swapped in after the engine's locks were built" do
    locks = engine("openlanes@one")
    OpenLanes::Locking.adapter = memory

    expect([locks.acquire(folder, "x"), memory.list(root).map(&:agent)]).to eq([true, ["openlanes@one"]])
  end
end

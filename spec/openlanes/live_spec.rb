# frozen_string_literal: true

RSpec.describe OpenLanes::Live do
  let(:store) { described_class.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/o/n", node: "me:1") }

  describe ".redis_url" do
    let(:config) { OpenLanes::Config.new(redis_url: "redis://config:6379/0") }

    it "takes the flag, then .openlanes.yml, then $REDIS_URL, then localhost" do
      expect([described_class.redis_url(option: "redis://flag/0", config:, env: { "REDIS_URL" => "redis://env/0" }),
              described_class.redis_url(option: " ", config:, env: { "REDIS_URL" => "redis://env/0" }),
              described_class.redis_url(config: OpenLanes::Config.new, env: { "REDIS_URL" => "redis://env/0" }),
              described_class.redis_url(config: OpenLanes::Config.new, env: {})])
        .to eq(%w[redis://flag/0 redis://config:6379/0 redis://env/0 redis://localhost:6379/0])
    end
  end

  # The suite sets Live.interviewer to nil before every example, which leaves
  # the lazy branch unrun; these clear it to reach Interviewer.from_env.
  describe ".interviewer" do
    before { described_class.remove_instance_variable(:@interviewer) }

    it "is nil without OPENROUTER_API_KEY" do
      stub_const("ENV", ENV.to_h.except("OPENROUTER_API_KEY"))

      expect(described_class.interviewer).to be_nil
    end

    it "is an Interviewer with one, built once and kept" do
      stub_const("ENV", ENV.to_h.merge("OPENROUTER_API_KEY" => "sk-or-test"))
      allow(OpenLanes::Live::Interviewer).to receive(:from_env).and_call_original

      2.times { described_class.interviewer }

      aggregate_failures do
        expect(described_class.interviewer).to be_a(OpenLanes::Live::Interviewer)
        expect(OpenLanes::Live::Interviewer).to have_received(:from_env).once
      end
    end
  end

  describe ".mask" do
    it "hides a password, and only a password" do
      expect(%w[redis://:pw@h:6379/0 rediss://user:pw@h/1 redis://h:6379/0].map { described_class.mask(it) })
        .to eq(%w[redis://:***@h:6379/0 rediss://user:***@h/1 redis://h:6379/0])
    end
  end

  describe ".redact" do
    it "hides the whole userinfo, user name included, and leaves a URL without one alone" do
      expect(%w[redis://:pw@h:6379/0 rediss://user:pw@h/1 redis://user@h/2 redis://h:6379/0].map { described_class.redact(it) })
        .to eq(%w[redis://:***@h:6379/0 rediss://:***@h/1 redis://:***@h/2 redis://h:6379/0])
    end
  end

  describe ".connect" do
    it "is Unavailable where nothing answers" do
      expect { described_class.connect("redis://127.0.0.1:1/15") }.to raise_error(described_class::Unavailable)
    end

    it "refuses a store that does not answer PING" do
      allow(OpenLanes::Live::Store).to receive(:new).and_return(instance_double(OpenLanes::Live::Store, ping: false))
      expect { described_class.connect("redis://x/0") }.to raise_error(described_class::Unavailable, /did not answer PING/)
    end

    context "when the store answers" do
      let(:answering) { instance_double(OpenLanes::Live::Store, ping: true) }

      before { allow(OpenLanes::Live::Store).to receive(:new).and_return(answering) }

      it "hands it back" do
        expect(described_class.connect("redis://x/0")).to be(answering)
      end
    end
  end

  it "builds a real store for an address without connecting" do
    expect(described_class.store("redis://127.0.0.1:1/15").url).to eq("redis://127.0.0.1:1/15")
  end

  it "builds this checkout's keys" do
    Dir.mktmpdir("openlanes-keys") do |root|
      expect(described_class.keys(root:).repo).to start_with("local/#{File.basename(root)}-")
    end
  end

  describe ".board" do
    before do
      store.hset(keys.nodes, "me:1", "{}")
      store.hset(keys.nodes, "them:2", "{}")
      store.hset(keys.nodes, "dead:3", "{}")
      store.set(keys.snapshot, JSON.generate(seq: 1, node: { host: "a", me: true }))
      store.set(keys.snapshot("them:2"), JSON.generate(seq: 7, node: { host: "b", me: true }))
    end

    it "is our snapshot and every other live node's, theirs never marked as ours" do
      expect(described_class.board(store:, keys:)).to eq(me: { "seq" => 1, "node" => { "host" => "a", "me" => true } },
        others: [{ "seq" => 7, "node" => { "host" => "b", "me" => false } }])
    end

    it "forgets nodes whose snapshot has expired, so the registry does not grow forever" do
      described_class.board(store:, keys:)
      expect(store.hgetall(keys.nodes).keys).to eq(%w[me:1 them:2])
    end

    it "has no snapshot of ours while our engine is down" do
      store.del(keys.snapshot)
      expect(described_class.board(store:, keys:)[:me]).to be_nil
    end
  end

  describe ".enqueue" do
    it "queues a well-formed command and answers accepted" do
      aggregate_failures do
        expect(described_class.enqueue(store:, keys:, input: { "id" => "01J", "kind" => "stop_all" }).status).to eq("accepted")
        expect(JSON.parse(store.xrange(keys.commands).first.fields["json"])).to include("id" => "01J", "kind" => "stop_all")
      end
    end

    it "queues nothing malformed" do
      expect { described_class.enqueue(store:, keys:, input: { "id" => "01J", "kind" => "nope" }) }
        .to raise_error(OpenLanes::Live::Command::Invalid)
      expect(store.xlen(keys.commands)).to eq(0)
    end
  end

  describe ".replies" do
    let!(:first) { store.xadd(keys.replies, { json: '{"id":"a"}' }) }

    before { store.xadd(keys.replies, { json: '{"id":"b"}' }) }

    it "reads the replies after an id" do
      expect(described_class.replies(store:, keys:, after: first).map(&:last)).to eq([{ "id" => "b" }])
    end
  end
end

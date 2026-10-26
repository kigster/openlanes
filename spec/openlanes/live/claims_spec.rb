# frozen_string_literal: true

RSpec.describe OpenLanes::Live::Claims do
  subject(:claims) { described_class.new(store:, keys:) }

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/o/n", node: "me:1") }
  let(:theirs) { described_class.new(store:, keys: keys.with(node: "them:2")) }

  it "takes a free plan for ninety seconds, and keeps it when asked again" do
    aggregate_failures do
      expect(claims.claim("004.00")).to be(true)
      expect(claims.claim("004.00")).to be(true)
      expect(store.ttl(keys.claim("004.00"))).to be_between(89, 90)
      expect(claims.held).to eq(%w[004.00])
      expect(claims.held_by("004.00")).to eq("me:1")
      expect(claims.foreign?("004.00")).to be(false)
    end
  end

  it "does not take a plan another node holds, and knows it is theirs" do
    theirs.claim("004.00")
    aggregate_failures do
      expect(claims.claim("004.00")).to be(false)
      expect(claims.held).to eq([])
      expect(claims.foreign?("004.00")).to be(true)
      expect(claims.foreign?("005.00")).to be(false)
    end
  end

  it "renews what it holds, and lets go of a claim that passed to another node" do
    claims.claim("004.00")
    claims.claim("005.00")
    store.set(keys.claim("005.00"), "them:2")
    aggregate_failures do
      expect(claims.renew).to eq(%w[005.00])
      expect(claims.held).to eq(%w[004.00])
    end
  end

  # W32: a Redis that restarted empty lost every claim. That is not another
  # machine taking the plans, and the agents on them must not be stopped.
  it "takes back a claim that vanished, and still loses one another node took" do
    claims.claim("004.00")
    claims.claim("005.00")
    store.del(keys.claim("004.00"), keys.claim("005.00"))
    theirs.claim("005.00")

    aggregate_failures do
      expect(claims.renew).to eq(%w[005.00])
      expect(claims.held_by("004.00")).to eq("me:1")
      expect(store.ttl(keys.claim("004.00"))).to be_between(89, 90)
    end
  end

  it "releases only its own claims" do
    claims.claim("004.00")
    theirs.claim("005.00")
    claims.release_all
    aggregate_failures do
      expect(claims.held_by("004.00")).to be_nil
      expect(claims.release("005.00")).to be(false)
      expect(claims.held_by("005.00")).to eq("them:2")
    end
  end

  describe "#hold" do
    context "when every plan is free" do
      let!(:taken) { claims.hold(%w[004.00 005.00]) }

      it { expect(taken).to eq([]) }
      it { expect(claims.held).to eq(%w[004.00 005.00]) }

      # Between one agent and the next the run keeps its plans.
      it "keeps a pinned plan through a plain release" do
        aggregate_failures do
          expect(claims.release("004.00")).to be(false)
          expect(claims.held_by("004.00")).to eq("me:1")
        end
      end

      it "lets go of everything at the end of the run" do
        claims.release_all
        expect([claims.held, claims.held_by("004.00"), claims.held_by("005.00")]).to eq([[], nil, nil])
      end
    end

    context "when another node holds one of them" do
      before { theirs.claim("005.00") }

      let!(:taken) { claims.hold(%w[004.00 005.00]) }

      it "names the plan and its holder" do
        expect(taken).to eq([described_class::Taken.new(ordinal: "005.00", holder: "them:2")])
      end

      # All or none: the free plan is not left claimed behind a refusal.
      it "keeps none of them" do
        expect([claims.held, claims.held_by("004.00")]).to eq([[], nil])
      end
    end
  end
end

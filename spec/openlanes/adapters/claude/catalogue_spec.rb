# frozen_string_literal: true

require "net/http"

RSpec.describe OpenLanes::Adapters::Claude::Catalogue do
  # A canned `Net::HTTPResponse`, as the fetch would return one.
  def reply(code, body)
    response = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s).new("1.1", code.to_s, "")
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  def row(id, name, created, window: 1_000_000)
    { "type" => "model", "id" => id, "display_name" => name, "created_at" => created, "max_input_tokens" => window }
  end

  let(:dir) { Dir.mktmpdir("catalogue") }
  let(:cache) { File.join(dir, "models.json") }
  let(:now) { Time.utc(2026, 11, 12, 20, 0, 0) }
  let(:requests) { [] }
  let(:pages) do
    [
      { "data" => [row("claude-opus-6", "Claude Opus 6", "2026-11-01T00:00:00Z"),
                   row("claude-sonnet-5-5", "Claude Sonnet 5.5", "2026-06-01T00:00:00Z"),
                   { "type" => "model", "id" => "not-a-claude", "display_name" => "Other" }],
        "has_more" => true, "last_id" => "claude-sonnet-5-5" },
      { "data" => [row("claude-fable-5-1", "Claude Fable 5.1", "2026-08-01T00:00:00Z"),
                   row("claude-haiku-4-5", "Claude Haiku 4.5", "2025-10-01T00:00:00Z", window: 200_000)],
        "has_more" => false, "last_id" => "claude-haiku-4-5" }
    ]
  end
  let(:fetch) do
    lambda do |request|
      requests << request
      reply(200, JSON.generate(pages[(requests.size - 1) % pages.size]))
    end
  end
  let(:env) { { "ANTHROPIC_API_KEY" => "sk-test" } }

  after { FileUtils.rm_rf(dir) }

  def catalogue(**overrides)
    described_class.new(fetch:, cache:, env:, now: -> { now }, **overrides)
  end

  describe "fetching" do
    it "walks every page, keeps the Claude models, and orders them by tier then version" do
      expect(catalogue.models.map(&:id)).to eq(%w[claude-fable-5-1 claude-opus-6 claude-sonnet-5-5 claude-haiku-4-5])
    end

    it "authenticates with the API key and asks for the next page by its last id" do
      catalogue.models
      expect(requests.map { [it["x-api-key"], it["anthropic-version"], it.uri.query] })
        .to eq([["sk-test", "2023-06-01", "limit=100"], ["sk-test", "2023-06-01", "limit=100&after_id=claude-sonnet-5-5"]])
    end

    it "takes labels and windows from Anthropic, prices from the shipped list, and guesses the rest" do
      opus, haiku = catalogue.models.values_at(1, 3)
      expect([opus.label, opus.rate_in, opus.estimated, opus.context, haiku.label, haiku.rate_in, haiku.estimated, haiku.context])
        .to eq(["Opus 6", 4, true, 1_000_000, "Haiku 4.5", 1, false, 200_000])
    end

    it "says where the list came from" do
      expect(catalogue.source).to eq("Anthropic (fetched just now)")
    end

    it "sends an OAuth token as a bearer with the beta header" do
      catalogue(env: { "ANTHROPIC_AUTH_TOKEN" => "tok" }).models
      expect([requests.first["authorization"], requests.first["anthropic-beta"]]).to eq(["Bearer tok", "oauth-2025-04-20"])
    end

    it "writes what it fetched to the cache, with the time" do
      catalogue.models
      data = JSON.parse(File.read(cache))
      expect([data["fetched_at"], data["models"].size, data["models"][1]["estimated"]]).to eq(["2026-11-12T20:00:00Z", 4, true])
    end
  end

  describe "the cache" do
    it "is read instead of fetching while it is fresh" do
      catalogue.models
      later = catalogue(now: -> { now + 3600 })
      expect([later.models.map(&:id), later.source, requests.size])
        .to eq([%w[claude-fable-5-1 claude-opus-6 claude-sonnet-5-5 claude-haiku-4-5], "cache (1 hour old)", 2])
    end

    it "is fetched again once it is a day old" do
      catalogue.models
      catalogue(now: -> { now + described_class::TTL }).models
      expect(requests.size).to eq(4)
    end

    it "stands in, however old, when the fetch fails" do
      catalogue.models
      failing = catalogue(now: -> { now + (3 * 86_400) }, fetch: ->(_) { reply(500, "down") })
      expect([failing.models.size, failing.source]).to eq([4, "cache (3 days old, fetch failed)"])
    end

    it "is ignored when it cannot be read" do
      File.write(cache, "not json")
      fresh = catalogue
      expect([fresh.models.size, fresh.source]).to eq([4, "Anthropic (fetched just now)"])
    end
  end

  describe "falling back" do
    it "ships its own list when there is no credential, and says so" do
      offline = catalogue(env: {})
      expect([offline.models, offline.source]).to eq([OpenLanes::Adapters::Claude::Pricing::BUNDLED, "bundled list (no ANTHROPIC_API_KEY)"])
    end

    it "never fetches when told to stay offline, even with a key" do
      offline = catalogue(env: env.merge("OPENLANES_MODELS_OFFLINE" => "1"))
      expect([offline.models, offline.source, requests]).to eq([OpenLanes::Adapters::Claude::Pricing::BUNDLED, "bundled list (OPENLANES_MODELS_OFFLINE is set)", []])
    end

    it "ships its own list when the fetch fails and nothing is cached, and logs why" do
      failing = catalogue(fetch: ->(_) { reply(401, "{}") })
      allow(OpenLanes::UI).to receive(:log).and_call_original
      expect([failing.models, failing.source]).to eq([OpenLanes::Adapters::Claude::Pricing::BUNDLED, "bundled list (fetch failed)"])
      expect(OpenLanes::UI).to have_received(:log).with("model list not fetched: Anthropic answered 401 ", level: :warn)
    end

    it "treats a list with no Claude models as a failed fetch" do
      empty = catalogue(fetch: ->(_) { reply(200, JSON.generate("data" => [], "has_more" => false)) })
      expect(empty.source).to eq("bundled list (fetch failed)")
    end

    it "treats a timeout as a failed fetch" do
      slow = catalogue(fetch: ->(_) { raise Net::OpenTimeout, "execution expired" })
      expect(slow.source).to eq("bundled list (fetch failed)")
    end
  end

  describe "#find" do
    subject(:bundled) { catalogue(env: {}) }

    it "prices an id it has never seen by its tier, and refuses one in no tier" do
      expect([bundled.find("claude-sonnet-7")&.estimated, bundled.find("claude-mythos-5-1"), bundled.find("gpt-5")])
        .to eq([true, nil, nil])
    end
  end

  describe ".label_from" do
    it "reads a label out of an id" do
      expect(%w[claude-opus-5-5 claude-sonnet-5 claude-fable-5-1].map { OpenLanes::Adapters::Claude::Pricing.label_from(it) })
        .to eq(["Opus 5.5", "Sonnet 5", "Fable 5.1"])
    end
  end

  describe ".current" do
    after { described_class.reset! }

    it "is built once and forgotten on reset" do
      first = described_class.current
      expect([described_class.current.equal?(first), described_class.reset!, described_class.current.equal?(first)])
        .to eq([true, nil, false])
    end
  end
end

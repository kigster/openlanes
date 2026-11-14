# frozen_string_literal: true

require "rack/test"
require "tmpdir"

# GET and PUT /api/settings through rack-test, against a real main checkout
# whose `origin` is a bare repository. Nothing in git is stubbed.
RSpec.describe "/api/settings", :origin do
  include Rack::Test::Methods

  let(:tmp) { Dir.mktmpdir("settings-api") }
  let(:main) { File.join(tmp, "main") }
  let(:origin) { File.join(tmp, "origin.git") }
  let(:file) { File.join(main, OpenLanes::Config::FILE) }
  let(:context) do
    plans = File.join(main, ".plans")
    FileUtils.mkdir_p(plans)
    OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(OpenLanes::Live.memory_store),
      keys: OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb"),
      plans_dir: plans,
      url: "redis://localhost:6379/3",
      dist: File.join(tmp, "dist"))
  end
  let(:app) { OpenLanes::Web.app(context) }
  let(:body) { JSON.parse(last_response.body) }
  let(:etag) { OpenLanes::Web::Settings.etag(main) }

  after { FileUtils.rm_rf(tmp) }

  before do
    FileUtils.mkdir_p(main)
    File.write(file, "jobs: 2\n")
    publish_with_origin(main, tmp)
    header "Host", "127.0.0.1:11000"
  end

  def put_settings(values, token: context.csrf, if_match: etag)
    header "X-CSRF-Token", token if token
    header "If-Match", if_match if if_match
    header "Content-Type", "application/json"
    put "/api/settings", JSON.generate(values:)
  end

  def origin_main = git!(origin, "rev-parse", "main")

  it "answers the schema, keys, values, defaults, etag and branch" do
    get "/api/settings"

    expect(last_response.status).to eq(200)
    expect(body.keys).to eq(%w[schema keys values defaults etag branch])
    expect(body).to include("keys" => OpenLanes::Config::KEYS, "values" => { "jobs" => 2 }, "etag" => etag, "branch" => "main")
    expect(body.dig("schema", "properties", "commands", "properties")).to include("run")
  end

  it "answers 200 unchanged when nothing differs" do
    before = origin_main
    put_settings({ "jobs" => 2 })

    expect([last_response.status, body]).to eq([200, { "changed" => false }])
    expect(origin_main).to eq(before)
  end

  it "writes, commits and pushes a change" do
    put_settings({ "jobs" => 6 })

    expect(last_response.status).to eq(200)
    expect(body).to include("changed" => true, "commit" => origin_main, "etag" => OpenLanes::Web::Settings.etag(main))
    expect(git!(origin, "show", "main:#{OpenLanes::Config::FILE}")).to include("jobs: 6")
  end

  it "answers 422 with each refused field's path" do
    put_settings({ "merge" => { "by" => "robot" } })

    expect(last_response.status).to eq(422)
    expect(body["errors"].map { it["path"] }).to eq([%w[merge by]])
    expect(File.read(file)).to eq("jobs: 2\n")
  end

  it "answers 422 when values is not an object" do
    header "X-CSRF-Token", context.csrf
    header "If-Match", etag
    header "Content-Type", "application/json"
    put "/api/settings", JSON.generate(values: [])

    expect(last_response.status).to eq(422)
    expect(body["errors"]).to eq([{ "path" => [], "message" => "values is a JSON object" }])
  end

  {
    "not_on_main"         => ->(spec) { spec.git!(spec.main, "checkout", "-q", "-b", "other") },
    "dirty_config"        => ->(spec) { File.write(spec.file, "jobs: 9\n") },
    "cannot_fast_forward" => ->(spec) { spec.commit_file(spec.main, "mine.txt", "x\n") }
  }.each do |refusal, setup|
    it "answers 409 #{refusal} with its reason" do
      setup.call(self)
      put_settings({ "jobs" => 3 }, if_match: OpenLanes::Web::Settings.etag(main))

      expect(last_response.status).to eq(409)
      expect(body).to include("refusal" => refusal, "reason" => a_string_matching(/\S/))
    end
  end

  it "answers 409 stale_etag for an old etag" do
    put_settings({ "jobs" => 3 }, if_match: "old")
    expect([last_response.status, body["refusal"]]).to eq([409, "stale_etag"])
  end

  it "answers 428 without If-Match" do
    put_settings({ "jobs" => 3 }, if_match: nil)
    expect(last_response.status).to eq(428)
  end

  it "answers 403 without the CSRF token" do
    put_settings({ "jobs" => 3 }, token: "wrong")

    expect(last_response.status).to eq(403)
    expect(File.read(file)).to eq("jobs: 2\n")
  end
end

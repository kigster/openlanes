# frozen_string_literal: true

require "json"
require "rack/mock"

RSpec.describe OpenLanes::Web::RequestLog do
  subject(:middleware) { described_class.new(app, clock:) }

  let(:dir) { Dir.mktmpdir("request-log") }
  let(:file) { File.join(dir, "log", "development.log") }
  # Every reading moves the clock on by 12.5ms, so a duration is an assertion.
  let(:clock) do
    now = 100.0
    -> { now += 0.0125 }
  end
  let(:status) { 200 }
  let(:type) { "application/json" }
  let(:app) { ->(_env) { [status, { "content-type" => type }, ["{}"]] } }

  before { open_log(file, format: "json", name: "web") }

  after { FileUtils.rm_rf(dir) }

  def get(path) = middleware.call(Rack::MockRequest.env_for(path))

  def entries = File.readlines(file).map { JSON.parse(it) }

  it "logs an API call with its method, path, status, page and duration" do
    get("/api/chat?page=tab-7")

    expect(entries).to contain_exactly(a_hash_including(
      "name"        => "web",
      "level"       => "info",
      "message"     => "GET /api/chat 200",
      "duration_ms" => 12.5,
      "payload"     => { "method" => "GET", "path" => "/api/chat", "status" => 200, "page" => "tab-7" }
    ))
  end

  context "when the app answers with an error" do
    let(:status) { 422 }

    it "logs the status it answered with" do
      get("/api/commands")

      expect(entries.first).to include("message" => "GET /api/commands 422", "payload" => a_hash_including("status" => 422))
    end
  end

  it "logs a page's own files and /healthz at debug, out of the API's way" do
    get("/assets/app.js")
    get("/healthz")

    expect(entries.map { it.values_at("level", "message") }).to eq([%w[debug GET\ /assets/app.js\ 200], %w[debug GET\ /healthz\ 200]])
  end

  it "leaves the page out when the request names none" do
    get("/api/board?page=")

    expect(entries.first["payload"]).not_to have_key("page")
  end

  context "when the app raises" do
    let(:app) { ->(_env) { raise ArgumentError, "bad" } }

    it "logs the failure as a 500 and raises it on" do
      expect { get("/api/board") }.to raise_error(ArgumentError, "bad")
      expect(entries.first).to include("level" => "error",
        "message" => "GET /api/board raised ArgumentError",
        "payload" => a_hash_including("status" => 500))
    end
  end

  context "with the event stream" do
    let(:type) { "text/event-stream" }

    it "logs the stream opening at once, and closing with how long it was open" do
      _status, _headers, body = get("/api/events?page=tab-7")
      opened = entries

      body.close

      aggregate_failures do
        expect(opened).to contain_exactly(a_hash_including("message" => "GET /api/events stream opened"))
        expect(opened.first).not_to have_key("duration_ms")
        expect(entries.last).to include("message" => "GET /api/events stream closed",
          "duration_ms" => 12.5,
          "payload" => a_hash_including("page" => "tab-7", "status" => 200))
      end
    end

    it "hands the body on untouched, so the stream still streams" do
      _status, _headers, body = get("/api/events")
      expect(body.enum_for(:each).to_a).to eq(["{}"])
    end
  end

  it "never fails a request over a log it cannot write" do
    broken = described_class.new(app, logger: Object.new)

    expect(broken.call(Rack::MockRequest.env_for("/api/board")).first).to eq(200)
  end

  it "is what Web.app serves the routes through" do
    context = instance_double(OpenLanes::Web::Context, dist: Dir.tmpdir, listen: OpenLanes::Web::Listen.parse(nil))

    expect(OpenLanes::Web.app(context)).to be_a(described_class)
  end
end

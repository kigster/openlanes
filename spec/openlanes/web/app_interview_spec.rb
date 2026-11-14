# frozen_string_literal: true

require "rack/test"

# The unblocker's interview over HTTP, answered by the demo's responder:
# open, two replies, a decision, and a confirm through the command gate.
RSpec.describe OpenLanes::Web::App, :tree do
  include Rack::Test::Methods

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:responder) { OpenLanes::Web::Demo::Interview }
  let(:context) do
    OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store),
      keys:,
      plans_dir: plans_root,
      url: "redis://localhost:6379/3",
      lifetime: 0.2,
      interview: responder,
      background:)
  end
  let(:later) { [] }
  let(:background) { ->(&work) { later << work } }
  let(:app) { OpenLanes::Web.app(context) }
  let(:path) { "/api/plans/002.00/questions/1/interview" }

  before { header "Host", "127.0.0.1:11000" }

  def body = JSON.parse(last_response.body)

  def files = Dir.glob(File.join(plans_root, "**", "*")).to_h { [it, File.file?(it) ? File.read(it) : nil] }

  def run_later = later.shift(later.size).each(&:call)

  def reply(id, text, token: context.csrf)
    header "X-CSRF-Token", token if token
    post path, JSON.generate(id:, text:), "CONTENT_TYPE" => "application/json"
  end

  def turns
    get path
    body["turns"]
  end

  it "opens with a question on the first read, and walks two replies to a decision" do
    expect(turns).to eq([])
    run_later
    first = turns.first
    expect(first).to include("from" => "unblocker", "kind" => "question")
    expect(first["options"].count { it["recommended"] }).to eq(1)

    reply("r1", first["options"].first["label"])
    expect([last_response.status, body["turn"]]).to match([202, include("id" => "r1", "from" => "you")])
    run_later
    reply("r2", "something only I would say")
    run_later

    decision = turns.last
    expect(decision).to include("kind" => "decision", "answer" => "Go ahead with the proposed approach; something only I would say")
    expect(turns.map { it["kind"] }).to eq(%w[question text question text decision])
  end

  it "shows the same conversation to a second reader, as a reload or a second machine would see it" do
    turns
    run_later
    reply("r1", "yes")
    run_later
    seen = turns
    other = OpenLanes::Web.app(context.with(background: ->(&_) {}))
    expect(Rack::MockRequest.new(other).get(path, "HTTP_HOST" => "127.0.0.1:11000").body).to eq(JSON.generate(turns: seen))
  end

  it "publishes each turn with its plan and question for the event stream" do
    turns
    run_later
    entries = OpenLanes::Live::Interview::Feed.new(store:, keys:).since("0-0").map(&:last)
    expect(entries.first).to include("plan" => "002.00", "number" => 1, "turn" => include("kind" => "question"))
  end

  it "writes nothing to the plan's files" do
    before = files
    turns
    run_later
    reply("r1", "yes")
    run_later
    expect(files).to eq(before)
  end

  it "refuses a reply without the session's token, and an empty one" do
    reply("r1", "yes", token: nil)
    expect(last_response.status).to eq(403)
    reply("r1", "  ")
    expect([last_response.status, body["error"]]).to eq([422, "a turn needs text"])
  end

  it "answers 404 for a path that names no plan or question" do
    get "/api/plans/x/questions/1/interview"
    expect(last_response.status).to eq(404)
    get "/api/plans/002.00/questions/B1/interview"
    expect(last_response.status).to eq(404)
  end

  context "when nothing answers interviews here" do
    let(:responder) { nil }

    it "says so on a reply, and starts nothing on a read" do
      expect(turns).to eq([])
      reply("r1", "yes")
      expect([last_response.status, later]).to eq([503, []])
    end
  end

  it "takes confirm_interview through the command gate" do
    header "X-CSRF-Token", context.csrf
    post "/api/commands",
      JSON.generate(id: "01JC", kind: "confirm_interview", plan: "002.00", agent: nil, payload: { question: "1", turn: "u5" }),
      "CONTENT_TYPE" => "application/json"
    expect(last_response.status).to eq(202)
  end
end

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

  let(:asked) { "# Blocked\n\n## B1 Rebase\n\nShould I rebase?\n\na) yes (Recommended)\nb) no\n" }
  let(:blocked_md) { File.join(OpenLanes::Plans.tree(plans_root).find("002.00").feature.path, "blocked.md") }

  before do
    header "Host", "127.0.0.1:11000"
    plans { |t| t.plan "002.00", :blocked, "rebase", files: { "spec.md" => "# Spec\n", "blocked.md" => asked } }
  end

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

  it "serves each turn's place in the conversation, in order" do
    turns
    run_later
    reply("r1", "yes")
    seqs = turns.map { it["seq"].split("-").map(&:to_i) }
    expect(seqs).to eq(seqs.sort).and eq(seqs.uniq)
    expect(body["turns"].last["seq"]).to eq(seqs.last.join("-"))
  end

  # Issue 252: a read used to start a model run on any path that looked like a question.
  describe "a question that is not open" do
    def refused = [last_response.status, body["error"], later]

    it "starts nothing for a plan that asks no such question" do
      get "/api/plans/002.00/questions/7/interview"
      expect(refused).to eq([409, "plan 002.00 has no open question 7 to talk through", []])
      get "/api/plans/099.00/questions/1/interview"
      expect(refused).to eq([409, "plan 099.00 has no open question 1 to talk through", []])
    end

    it "starts nothing once it is answered, forgets what was said, and takes no more replies" do
      turns
      run_later
      File.write(blocked_md, "#{asked}\n## A1\n\nyes\n")
      get path
      expect(refused).to eq([409, "plan 002.00 has no open question 1 to talk through", []])
      expect(OpenLanes::Live::Interview.new(store:, keys:, plan: "002.00", number: 1).history).to be_empty
      reply("r1", "yes")
      expect(refused).to eq([409, "plan 002.00 has no open question 1 to talk through", []])
    end

    it "starts over when the plan blocks again with a new question under the same number" do
      turns
      run_later
      reply("r1", "yes")
      run_later
      File.write(blocked_md, "# Blocked\n\n## B1 Database\n\nPostgres or SQLite?\n")
      expect(turns).to eq([])
      run_later
      expect(turns.map { it["kind"] }).to eq(%w[question])
    end
  end

  context "with the demo, where no blocked.md says what is open" do
    let(:demo) { instance_double(OpenLanes::Web::Demo) }
    let(:app) { OpenLanes::Web.app(context.with(demo:)) }
    let(:question) { { "number" => 1, "kind" => "block", "heading" => "B1 Rebase", "body" => "Should I rebase?" } }

    def publish(*questions)
      store.set(keys.snapshot(keys.node), JSON.generate("node" => { "host" => "studio" }, "plans" => [{ "ordinal" => "007.00", "questions" => questions }]))
    end

    it "talks through a question the demo's board holds open, and no other" do
      publish(question, question.merge("number" => 2, "kind" => "extension"), question.merge("number" => 3, "kind" => nil))
      get "/api/plans/007.00/questions/1/interview"
      expect([last_response.status, later.size]).to eq([200, 1])
      get "/api/plans/007.00/questions/2/interview"
      expect(last_response.status).to eq(409)
      get "/api/plans/007.00/questions/3/interview"
      expect(last_response.status).to eq(200)
      get path
      expect(last_response.status).to eq(409)
    end

    it "starts nothing before the demo has published a board" do
      get "/api/plans/007.00/questions/1/interview"
      expect([last_response.status, later]).to eq([409, []])
    end

    it "starts over when the board asks something else under the number" do
      publish(question)
      get "/api/plans/007.00/questions/1/interview"
      run_later
      publish(question.merge("body" => "Postgres or SQLite?"))
      get "/api/plans/007.00/questions/1/interview"
      expect(body["turns"]).to eq([])
    end
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

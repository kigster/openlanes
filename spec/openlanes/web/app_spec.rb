# frozen_string_literal: true

require "rack/test"

# Every route of contract.md, "HTTP", driven in process through rack-test
# over the in-memory store: no Puma, no Redis, no browser.
RSpec.describe OpenLanes::Web::App, :tree do
  include Rack::Test::Methods

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:dist) do
    File.join(File.dirname(plans_root), "dist").tap do |dir|
      FileUtils.mkdir_p(File.join(dir, "assets"))
      File.write(File.join(dir, "index.html"), "<!doctype html><title>control room</title>")
      File.write(File.join(dir, "assets", "app.js"), "console.log('hi')")
    end
  end
  let(:node) do
    OpenLanes::Live::Node.new(id: "aaaa", user: "pat", host: "box", ip: nil, checkout: "~/widgets", checkout_id: "bbbb")
  end
  let(:context) do
    OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store),
      keys:,
      plans_dir: plans_root,
      url: "redis://user:hunter2@localhost:6379/3",
      dist:,
      node:,
      lifetime: 0.2,
      copilot: OpenLanes::Web::Demo::COPILOT,
      background:)
  end
  # Work the app starts apart from a request waits here until the example
  # runs it, so an example can look between the 202 and the answer.
  let(:later) { [] }
  let(:background) { ->(&work) { later << work } }
  let(:app) { OpenLanes::Web.app(context) }
  let(:snapshot) { { seq: 7, node: { id: "aaaa", user: "pat", host: "box", checkout: "~/widgets", me: true }, plans: [] } }
  let(:command) { { id: "01JCMD", kind: "stop_all", plan: nil, agent: nil, payload: {} } }
  let(:body) { JSON.parse(last_response.body) }

  before { header "Host", "127.0.0.1:11000" }

  def post_command(payload, token: context.csrf)
    header "X-CSRF-Token", token if token
    post "/api/commands", payload.is_a?(String) ? payload : JSON.generate(payload), "CONTENT_TYPE" => "application/json"
  end

  describe "GET /healthz" do
    before { get "/healthz" }

    it "answers ok with the Redis address, password masked" do
      expect([last_response.status, last_response.body]).to eq([200, "ok redis://user:***@localhost:6379/3\n"])
    end

    context "when Redis stops answering" do
      before do
        allow(store).to receive(:ping).and_raise(OpenLanes::Live::Unavailable, "Redis at redis://localhost is unavailable")
        get "/healthz"
      end

      it "answers 503 with the reason" do
        expect([last_response.status, body["error"]]).to eq([503, "Redis at redis://localhost is unavailable"])
      end
    end
  end

  describe "GET /api/session" do
    before { get "/api/session" }

    it "hands out the token, the node and the repository" do
      expect(body).to include("csrf" => context.csrf, "repo" => "github.com/acme/widgets", "node" => include("user" => "pat"))
    end

    it "is never cached" do
      expect(last_response.headers["Cache-Control"]).to include("no-store")
    end

    context "when the engine has published" do
      before do
        store.set(keys.snapshot, JSON.generate(snapshot))
        get "/api/session"
      end

      it "names the node as the engine describes it" do
        expect(body["node"]).to include("checkout" => "~/widgets", "me" => true)
      end
    end
  end

  describe "GET /api/board" do
    before do
      store.set(keys.snapshot, JSON.generate(snapshot))
      get "/api/board"
    end

    it "answers the Board now" do
      expect(body).to eq("me" => JSON.parse(JSON.generate(snapshot)), "others" => [])
    end
  end

  # Plan 012: the Preview tab's toolbar, onto the app runner's stream.
  describe "POST /api/apps/commands" do
    def post_app(payload, token: context.csrf)
      header "X-CSRF-Token", token if token
      post "/api/apps/commands", JSON.generate(payload), "CONTENT_TYPE" => "application/json"
    end

    def queued = store.xrange(keys.app_commands).map { JSON.parse(it.fields["json"]) }

    it "queues a restart for the runner and answers 202 with what it queued" do
      post_app({ plan: "12", action: "restart", target: "backend" })
      expect([last_response.status, body, queued]).to eq(
        [202, { "plan" => "012.00", "action" => "restart", "target" => "backend" },
         [{ "plan" => "012.00", "action" => "restart", "target" => "backend" }]]
      )
    end

    it "queues a stop with no target" do
      post_app({ plan: "012.00", action: "stop" })
      expect(queued).to eq([{ "plan" => "012.00", "action" => "stop", "target" => nil }])
    end

    {
      "an unknown action"   => [{ plan: "012.00", action: "rebuild" }, /action must be one of restart, stop/],
      "no plan"             => [{ action: "stop" }, /plan must be a plan number/],
      "a target with a ../" => [{ plan: "012.00", action: "restart", target: "../web" }, /target must be backend or a process name/]
    }.each do |what, (payload, message)|
      it "answers 422 for #{what} and queues nothing" do
        post_app(payload)
        expect([last_response.status, body["error"], queued]).to match([422, message, []])
      end
    end

    it "answers 403 without the token" do
      post_app({ plan: "012.00", action: "stop" }, token: nil)
      expect([last_response.status, queued]).to eq([403, []])
    end
  end

  describe "POST /api/commands" do
    context "with the session's token" do
      before { post_command(command) }

      it "queues the command and answers 202 accepted" do
        aggregate_failures do
          expect(last_response.status).to eq(202)
          expect(body).to include("id" => "01JCMD", "status" => "accepted")
          expect(store.xlen(keys.commands)).to eq(1)
        end
      end
    end

    context "without a token" do
      before { post_command(command, token: nil) }

      it "answers 403 and queues nothing" do
        expect([last_response.status, store.xlen(keys.commands)]).to eq([403, 0])
      end
    end

    context "with a stale token" do
      before { post_command(command, token: "0" * 64) }

      it "answers 403" do
        expect(last_response.status).to eq(403)
      end
    end

    context "with an invalid command" do
      before { post_command(command.merge(kind: "launch_missiles")) }

      it "answers 422 refused, with the reason, under the command's id" do
        expect([last_response.status, body["id"], body["status"], body["reason"]])
          .to match([422, "01JCMD", "refused", /unknown kind "launch_missiles"/])
      end
    end

    context "with a body that is not JSON" do
      before { post_command("{nope") }

      it "answers 422 with no id to name" do
        expect([last_response.status, body["id"], body["status"]]).to eq([422, "", "refused"])
      end
    end

    context "with a JSON body that is not an object" do
      before { post_command("[1, 2]") }

      it "answers 422" do
        expect(last_response.status).to eq(422)
      end
    end
  end

  describe "POST /api/interview" do
    def post_idea(payload, token: context.csrf)
      header "X-CSRF-Token", token if token
      post "/api/interview", JSON.generate(payload), "CONTENT_TYPE" => "application/json"
    end

    let(:question) do
      OpenLanes::Live::Interviewer::Question.new(context: "Who opens it?", options: %w[Accountant Anyone], recommended: 0)
    end

    it "answers with the interviewer's questions" do
      OpenLanes::Live.interviewer = ->(idea:) { idea == "CSV export" ? [question] : [] }
      post_idea({ idea: "CSV export" })
      expect([last_response.status, body]).to eq(
        [200, { "questions" => [{ "context" => "Who opens it?", "options" => %w[Accountant Anyone], "recommended" => 0 }] }]
      )
    end

    it "answers no questions, and why, without an interviewer" do
      post_idea({ idea: "CSV export" })
      expect([last_response.status, body["questions"], body["reason"]]).to eq([200, [], "no interviewer: OPENROUTER_API_KEY is not set"])
    end

    it "answers no questions, and why, when the interviewer fails" do
      OpenLanes::Live.interviewer = ->(idea:) { raise "timed out #{idea}" }
      post_idea({ idea: "CSV export" })
      expect([body["questions"], body["reason"]]).to eq([[], "the interviewer failed: timed out CSV export"])
    end

    it "answers 422 without an idea" do
      post_idea({ idea: " " })
      expect(last_response.status).to eq(422)
    end

    it "answers 403 without the token" do
      post_idea({ idea: "CSV export" }, token: nil)
      expect(last_response.status).to eq(403)
    end
  end

  describe "POST /api/copilot" do
    def post_message(payload, token: context.csrf)
      header "X-CSRF-Token", token if token
      post "/api/copilot", payload.is_a?(String) ? payload : JSON.generate(payload), "CONTENT_TYPE" => "application/json"
    end

    context "with the session's token" do
      before { post_message({ id: "01JMSG", text: "Why has 001 not moved?" }) }

      it "answers 202 with the person's turn" do
        expect([last_response.status, body]).to match([202, include("id" => "01JMSG", "from" => "you", "kind" => "text")])
      end

      it "answers before the copilot does: only the message is stored when the 202 goes out" do
        expect([store.xlen(keys.copilot), later.size]).to eq([1, 1])
      end

      it "then stores the responder's answer apart from the request" do
        later.each(&:call)
        expect(store.xrange(keys.copilot).map { JSON.parse(it.fields["json"])["id"] }).to eq(%w[01JMSG 01JMSG.1])
      end
    end

    context "with a slash command and a live engine (plan 020.00)" do
      before do
        store.set(keys.snapshot, JSON.generate(snapshot))
        post_message({ id: "01JCONC", text: "/concurrency 2" })
      end

      it "answers 202, queues it for the engine and starts no copilot" do
        queued = store.xrange(keys.commands).map { JSON.parse(it.fields["json"]) }
        expect([last_response.status, queued.map { it.values_at("id", "kind", "payload") }, later.size])
          .to eq([202, [["01JCONC", "set_concurrency", { "limit" => 2, "source" => "copilot" }]], 0])
      end
    end

    context "with a slash command and no engine" do
      before { post_message({ id: "01JSTOP", text: "/stop 20" }) }

      it "answers 503 and stores nothing" do
        expect([last_response.status, body["error"], store.xlen(keys.copilot), store.xlen(keys.commands)])
          .to eq([503, "no engine is running to apply /stop", 0, 0])
      end
    end

    context "with an unknown slash command" do
      before { post_message({ id: "01JFROB", text: "/frobnicate" }) }

      it "answers 202 with the usage already in the conversation, and starts no copilot" do
        expect([last_response.status, store.xlen(keys.copilot), later.size]).to eq([202, 2, 0])
      end
    end

    context "when nothing answers the copilot in this server" do
      let(:context) do
        OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store), keys:, plans_dir: plans_root, url: "memory://", background:)
      end

      before { post_message({ id: "01JMSG", text: "hi" }) }

      it "answers 503, stores nothing and starts nothing" do
        expect([last_response.status, body["error"], store.xlen(keys.copilot), later.size])
          .to eq([503, "the copilot is not running in this server", 0, 0])
      end
    end

    context "with the default background" do
      let(:background) { OpenLanes::Web::Context::THREAD }

      it "answers on a thread of its own" do
        post_message({ id: "01JMSG", text: "hi" })
        wait_until = Time.now + 2
        sleep 0.01 until store.xlen(keys.copilot) == 2 || Time.now > wait_until
        expect(store.xlen(keys.copilot)).to eq(2)
      end
    end

    context "without a token" do
      before { post_message({ id: "01JMSG", text: "hi" }, token: nil) }

      it "answers 403 and stores nothing" do
        expect([last_response.status, store.xlen(keys.copilot)]).to eq([403, 0])
      end
    end

    context "with no text" do
      before { post_message({ id: "01JMSG", text: "" }) }

      it "answers 422 with the reason" do
        expect([last_response.status, body["error"]]).to eq([422, "a message needs text"])
      end
    end
  end

  describe "the chat between machines" do
    let(:kim) { "1" * 24 }
    let(:page) { "page-0001" }

    def chat_post(action, payload = nil, token: context.csrf, **fields)
      payload ||= fields
      header "X-CSRF-Token", token if token
      post "/api/chat/#{action}", payload.is_a?(String) ? payload : JSON.generate(payload), "CONTENT_TYPE" => "application/json"
    end

    before do
      other = "#{kim}:cccc"
      store.hset(keys.nodes, other, "{}")
      store.set(keys.snapshot(other), JSON.generate(seq: 1, node: { id: kim, user: "kim", host: "lab", checkout: "~/w" }))
      context.chat.step
    end

    it "starts a chat with a machine on the board, naming it as user@host" do
      chat_post("start", page:, name: "Pat", machine: kim)
      context.chat.step
      get "/api/chat", page: page
      expect(body).to include("chat" => include("participants" => [include("name" => "Pat")]), "invites" => [])
    end

    # The verb table in plan 006's contract.md, which rey-frontend's page is
    # written against. An unknown verb is the route's own 404; every other
    # status means the verb reached the hub.
    it "accepts exactly the verbs in the contract's verb table" do
      contract = %w[start invite accept decline leave say presence]
      probed = (contract + %w[stop join shout]).to_h do |verb|
        chat_post(verb, page:)
        [verb, last_response.status == 404 && body["error"].to_s.start_with?("no such chat action")]
      end
      expect(probed.reject { |_, unknown| unknown }.keys).to eq(contract)
    end

    it "refuses a machine that is not on the board" do
      chat_post("start", page:, name: "Pat", machine: "2" * 24)
      expect([last_response.status, body["error"]]).to eq([422, "no machine #{"2" * 24} is on this Redis now"])
    end

    it "sends, idles and leaves" do
      chat_post("start", page:, name: "Pat", machine: kim)
      chat_post("say", page:, id: "01JMSG", text: "hi https://example.com")
      sent = [last_response.status, body["text"]]
      chat_post("presence", page:, idle: true)
      chat_post("leave", page:)
      expect(sent + [last_response.status, JSON.parse(last_response.body)]).to eq([202, "hi https://example.com", 202, {}])
    end

    it "answers 422 for a message over 4,000 characters" do
      chat_post("start", page:, name: "Pat", machine: kim)
      chat_post("say", page:, id: "01JMSG", text: "x" * 4001)
      expect([last_response.status, body["error"]]).to eq([422, "a message is at most 4000 characters"])
    end

    it "answers 409 for an invite that is not open, and 404 for an action it does not know" do
      chat_post("accept", page:, invite: "nope", name: "Pat")
      settled = last_response.status
      chat_post("decline", page:, invite: "nope")
      declined = last_response.status
      chat_post("wave", page:)
      expect([settled, declined, last_response.status]).to eq([409, 409, 404])
    end

    it "refuses a body that is not a JSON object" do
      chat_post("say", "[1]")
      array = body["error"]
      chat_post("say", "{nope")
      expect([array, last_response.status, JSON.parse(last_response.body)["error"]]).to match(["the body is a JSON object", 422, start_with("not JSON")])
    end

    it "refuses a write without the token" do
      chat_post("leave", page:, token: nil)
      expect(last_response.status).to eq(403)
    end

    it "refuses a page id that is not one" do
      get "/api/chat", page: "x"
      expect([last_response.status, body["error"]]).to match([422, start_with("page must be")])
    end
  end

  describe "GET /api/copilot" do
    before do
      header "X-CSRF-Token", context.csrf
      post "/api/copilot", JSON.generate(id: "01JMSG", text: "hello"), "CONTENT_TYPE" => "application/json"
      later.each(&:call)
      get "/api/copilot"
    end

    it "answers the conversation, oldest first, with the copilot's usage" do
      expect([body["turns"].map { it["id"] }, body["usage"]])
        .to eq([%w[01JMSG 01JMSG.1], { "model" => nil, "up" => 0, "down" => 0 }])
    end

    it "is never cached" do
      expect(last_response.headers["Cache-Control"]).to include("no-store")
    end
  end

  describe "GET /api/events" do
    before do
      store.set(keys.snapshot, JSON.generate(snapshot))
      get "/api/events"
    end

    it "is an event stream" do
      expect(last_response.headers["Content-Type"]).to start_with("text/event-stream")
    end

    it "opens with the reply cursor, then the board" do
      expect(last_response.body).to start_with("id: 0-0\nevent: cursor\ndata: {\"id\":\"0-0\"}\n\nevent: copilot_cursor\ndata: {\"id\":\"0-0\"}\n\nevent: board\ndata: {\"me\":{\"seq\":7")
    end
  end

  describe "POST /api/demo/reset" do
    context "without a demo" do
      before do
        header "X-CSRF-Token", context.csrf
        post "/api/demo/reset"
      end

      it "does not exist" do
        expect(last_response.status).to eq(404)
      end
    end

    context "with a demo" do
      let(:demo) { instance_double(OpenLanes::Web::Demo, reset: nil) }
      let(:context) do
        OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store), keys:, plans_dir: plans_root, url: "memory://", demo:)
      end

      it "puts the board back with the token" do
        header "X-CSRF-Token", context.csrf
        post "/api/demo/reset"
        expect(demo).to have_received(:reset)
      end

      it "answers 204" do
        header "X-CSRF-Token", context.csrf
        post "/api/demo/reset"
        expect(last_response.status).to eq(204)
      end

      it "refuses without it" do
        post "/api/demo/reset"
        expect(last_response.status).to eq(403)
      end
    end
  end

  describe "GET /api/plans/:ordinal/files/:name" do
    before do
      plans do |t|
        t.plan("004.00", :new, "web-control-room", files: { "spec.md" => "# The spec\n", "contract.md" => "# The contract\n", "secret.txt" => "no" })
      end
    end

    it "serves a plan file as Markdown" do
      get "/api/plans/004/files/spec.md"
      expect([last_response.status, last_response.content_type, last_response.body])
        .to eq([200, "text/markdown;charset=utf-8", "# The spec\n"])
    end

    it "serves the contract the two build halves share" do
      get "/api/plans/004.00/files/contract.md"
      expect(last_response.body).to eq("# The contract\n")
    end

    it "refuses a file that is not a plan document" do
      get "/api/plans/004.00/files/secret.txt"
      expect(last_response.status).to eq(404)
    end

    it "refuses a plan document the plan does not have" do
      get "/api/plans/004.00/files/plan.md"
      expect(body["error"]).to eq("004.00 has no plan.md")
    end

    it "refuses a plan that does not exist" do
      get "/api/plans/009.00/files/spec.md"
      expect(body["error"]).to eq("there is no plan 009.00")
    end

    it "refuses an ordinal that is not one" do
      get "/api/plans/abc/files/spec.md"
      expect(body["error"]).to eq("not a plan number")
    end

    %w[..%2F..%2F..%2Fetc%2Fpasswd ..%2Fspec.md %2Fetc%2Fpasswd].each do |name|
      it "never reads outside the plan folder for #{name}" do
        get "/api/plans/004.00/files/#{name}"
        expect(last_response.status).to eq(404)
      end
    end

    it "never reads outside the plans for a traversing ordinal" do
      get "/api/plans/..%2F..%2Fetc/files/spec.md"
      expect(last_response.status).to eq(404)
    end

    it "sends the SHA-256 of the bytes as a strong ETag" do
      get "/api/plans/004.00/files/spec.md"
      expect(last_response.headers["ETag"]).to eq(%("#{Digest::SHA256.hexdigest("# The spec\n")}"))
    end
  end

  describe "GET /api/plans/:ordinal/files" do
    before do
      plans do |t|
        t.plan("004.00", :new, "web-control-room", files: { "spec.md" => "# S\n", "blocked.md" => "# B\n", "secret.txt" => "no" })
        t.plan("005.00", :new, "empty")
      end
    end

    it "lists the plan files the folder has, in whitelist order" do
      get "/api/plans/004/files"
      expect([last_response.status, body]).to eq([200, { "files" => %w[spec.md blocked.md] }])
    end

    it "lists none for a folder with none" do
      get "/api/plans/005.00/files"
      expect([last_response.status, body]).to eq([200, { "files" => [] }])
    end

    it "refuses a plan that does not exist" do
      get "/api/plans/009.00/files"
      expect([last_response.status, body]).to eq([404, { "error" => "there is no plan 009.00" }])
    end
  end

  describe "PUT /api/plans/:ordinal/files/:name" do
    let(:spec_md) { "---\nstarts: research\n---\n\n# The spec\n" }
    let(:edited) { "---\nstarts: research\n---\n\n# The spec, edited\n" }
    let(:path) { File.join(Dir[File.join(plans_root, "004.00*")].first, "spec.md") }

    before do
      plans do |t|
        t.plan("004.00", :blocked, "web-control-room", files: { "spec.md" => spec_md, "blocked.md" => "## B1\n" })
      end
    end

    def etag_of(text) = %("#{Digest::SHA256.hexdigest(text)}")

    def save(name, text, if_match: etag_of(spec_md), token: context.csrf)
      header "X-CSRF-Token", token if token
      header "If-Match", if_match if if_match
      put "/api/plans/004.00/files/#{name}", text, "CONTENT_TYPE" => "text/markdown"
    end

    it "writes the file and answers with its new ETag" do
      save("spec.md", edited)
      expect([last_response.status, body, last_response.headers["ETag"], File.read(path)])
        .to eq([200, { "etag" => etag_of(edited) }, etag_of(edited), edited])
    end

    it "serves the saved body and ETag on the next GET" do
      save("spec.md", edited)
      get "/api/plans/004.00/files/spec.md"
      expect([last_response.body, last_response.headers["ETag"]]).to eq([edited, etag_of(edited)])
    end

    it "refuses without the CSRF token" do
      save("spec.md", edited, token: nil)
      expect([last_response.status, File.read(path)]).to eq([403, spec_md])
    end

    it "refuses blocked.md as read only" do
      save("blocked.md", "## B9\n", if_match: etag_of("## B1\n"))
      expect([last_response.status, body]).to eq([403, { "error" => "blocked.md is read only" }])
    end

    it "refuses a traversing name" do
      save("..%2Fspec.md", edited)
      expect([last_response.status, File.read(path)]).to eq([404, spec_md])
    end

    it "refuses a plan that does not exist" do
      header "X-CSRF-Token", context.csrf
      header "If-Match", etag_of(spec_md)
      put "/api/plans/009.00/files/spec.md", edited
      expect(last_response.status).to eq(404)
    end

    it "requires If-Match" do
      save("spec.md", edited, if_match: nil)
      expect([last_response.status, File.read(path)]).to eq([428, spec_md])
    end

    it "refuses a stale If-Match" do
      save("spec.md", edited, if_match: etag_of("older"))
      expect([last_response.status, body["error"], File.read(path)])
        .to eq([412, "spec.md changed since it was read; reload it", spec_md])
    end

    it "refuses changed frontmatter" do
      save("spec.md", edited.sub("starts: research", "starts: building"))
      expect([last_response.status, body["error"], File.read(path)]).to eq([422, "the frontmatter of spec.md is locked", spec_md])
    end

    context "when the plan has a live car" do
      before do
        plan = { ordinal: "004.00", cars: [{ agent: "luke-backend" }] }
        store.set(keys.snapshot, JSON.generate(snapshot.merge(plans: [plan])))
      end

      it "refuses with 409 and leaves the file alone" do
        save("spec.md", edited)
        expect([last_response.status, body["error"], File.read(path)])
          .to eq([409, "004.00 has an agent working on it; wait until it stops", spec_md])
      end
    end

    context "when the board lists the plan with no car" do
      before do
        store.set(keys.snapshot, JSON.generate(snapshot.merge(plans: [{ ordinal: "004.00", cars: [] }])))
      end

      it "saves" do
        save("spec.md", edited)
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe "an unknown API path" do
    before { get "/api/nothing" }

    it "answers 404 as JSON" do
      expect([last_response.status, body]).to eq([404, { "error" => "no such endpoint" }])
    end
  end

  describe "the page" do
    it "serves index.html at /" do
      get "/"
      expect([last_response.status, last_response.body]).to eq([200, "<!doctype html><title>control room</title>"])
    end

    it "serves index.html for the page's own routes" do
      get "/plans/004/drawer"
      expect(last_response.body).to include("control room")
    end

    it "serves the built assets" do
      get "/assets/app.js"
      expect(last_response.body).to eq("console.log('hi')")
    end

    it "answers 404 for an asset that is not there, rather than the page" do
      get "/assets/missing.js"
      expect(last_response.status).to eq(404)
    end

    context "when the page was never built" do
      let(:dist) { File.join(File.dirname(plans_root), "no-dist") }

      before { get "/" }

      it "answers 503 and says how to build it" do
        expect([last_response.status, last_response.body]).to match([503, %r{Run <code>just web-build</code> first}])
      end
    end
  end

  describe "the Host header" do
    before do
      header "Host", "attacker.example"
      get "/api/board"
    end

    it "is refused unless it names this machine" do
      expect(last_response.status).to eq(403)
    end
  end

  describe "the Host header, listening beyond loopback" do
    let(:listen) { OpenLanes::Web::Listen.parse("192.168.1.20") }
    let(:context) do
      OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store),
        keys:,
        plans_dir: plans_root,
        url: "redis://localhost:6379/3",
        dist:,
        node:,
        listen:)
    end

    def status_for(host)
      header "Host", host
      get "/api/board"
      last_response.status
    end

    it "answers the address listened on and loopback, and still refuses another site" do
      expect(%w[192.168.1.20:11000 127.0.0.1:11000 attacker.example].map { status_for(it) }).to eq([200, 200, 403])
    end
  end

  describe "a write from another origin" do
    before do
      header "Origin", "http://attacker.example"
      post_command(command)
    end

    it "is refused before the token is looked at" do
      expect([last_response.status, store.xlen(keys.commands)]).to eq([403, 0])
    end
  end
end

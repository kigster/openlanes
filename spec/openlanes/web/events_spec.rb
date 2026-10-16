# frozen_string_literal: true

# The event stream's loop, run for a few ticks against the in-memory store
# with a clock the example moves, so pings and lifetimes cost no real time.
RSpec.describe OpenLanes::Web::Events do
  subject(:events) { described_class.new(context:, store:, last_id:, page:, clock:, waiter:) }

  # An `out` the loop writes to, which can be closed from inside a write.
  let(:out_class) do
    Class.new do
      def initialize(&on_write)
        @frames = []
        @on_write = on_write
        @closed = false
      end

      attr_reader :frames

      def <<(frame)
        @frames << frame
        @on_write&.call(frame, self)
        self
      end

      def close = @closed = true
      def closed? = @closed
    end
  end

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:last_id) { nil }
  let(:page) { nil }
  let(:now) { [0.0] }
  let(:clock) { -> { now.first } }
  let(:lifetime) { 1.25 }
  let(:context) do
    OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store),
      keys:,
      plans_dir: "/nowhere",
      url: "memory://",
      ping_every: 0.5,
      lifetime:)
  end
  let(:out) { out_class.new }
  let(:frames) { out.frames }
  # Each wait for news advances the clock a quarter second, then runs the
  # example's block with the wait's number, standing in for whatever a
  # nudge would have woken the stream for.
  let(:on_tick) { [nil] }
  let(:waiter) do
    ticks = [0]
    lambda do |_, _|
      ticks[0] += 1
      now[0] += 0.25
      on_tick.first&.call(ticks.first)
    end
  end

  def publish(seq, node: keys.node)
    store.hset(keys.nodes, node, "{}")
    store.set(keys.snapshot(node), JSON.generate(seq:, node: { id: node, checkout: "~/w", host: node }))
  end

  def reply(id) = store.xadd(keys.replies, { json: JSON.generate(id:, status: "done", reason: nil, at: "2026-10-13T09:00:00Z") })

  def run_ticks(&block)
    on_tick[0] = block
    events.run(out)
  end

  describe ".frame" do
    it "writes a named event with its data as JSON" do
      expect(described_class.frame("board", { a: 1 })).to eq("event: board\ndata: {\"a\":1}\n\n")
    end

    it "carries an id when there is one" do
      expect(described_class.frame("reply", {}, id: "1-0")).to eq("id: 1-0\nevent: reply\ndata: {}\n\n")
    end
  end

  describe "#run" do
    before { publish(1) }

    # The first frame, which hands the browser a Last-Event-ID before any
    # reply has.
    let(:opening) { frames.first }

    context "when nothing changes" do
      before { run_ticks }

      it "opens with a cursor event at the start of an empty reply stream" do
        expect(opening).to eq("id: 0-0\nevent: cursor\ndata: {\"id\":\"0-0\"}\n\n")
      end

      it "sends the board once, then only pings" do
        expect(frames.grep(/\Aevent: board/).size).to eq(1)
      end

      it "pings every ping_every seconds" do
        expect(frames.count(": ping\n\n")).to eq(2)
      end
    end

    context "when a snapshot's seq changes and a reply arrives" do
      before do
        reply("01OLD")
        run_ticks do |tick|
          publish(2) if tick == 1
          reply("01NEW") if tick == 2
        end
      end

      it "sends the cursors, a board event, then the new board, then the reply" do
        expect(frames.reject { it == ": ping\n\n" }.map { it[/event: (\w+)/, 1] }).to eq(%w[cursor copilot_cursor board board reply])
      end

      it "opens with a cursor at the newest reply already written" do
        expect(opening).to start_with("id: #{store.xrange(keys.replies).first.id}\nevent: cursor\n")
      end

      it "sends the reply with its stream id, and leaves out the ones from before it connected" do
        expect(frames.grep(/event: reply/)).to contain_exactly(match(/\Aid: \d+-\d+\nevent: reply\ndata: \{"id":"01NEW"/))
      end
    end

    # Plan 012: the apps on this machine, from the runner's listing.
    context "when an app is running and changes" do
      def app(state, process = "web") = OpenLanes::Apps::Status.new(plan: "012.00", branch: "b", process:, state:, port: 11_101)

      def listing(*statuses) = OpenLanes::Apps::Listing.write(store:, keys:, plan: "012.00", statuses:)

      def named(event) = frames.grep(/event: #{event}\n/).map { JSON.parse(it[/data: (.*)\n\n\z/, 1]) }

      before do
        listing(app("starting", "api"), app("starting"))
        run_ticks do |tick|
          listing(app("ready", "api"), app("starting")) if tick == 1
          listing(app("ready", "api"), app("ready")) if tick == 2
          OpenLanes::Apps::Listing.remove(store:, keys:, plan: "012.00") if tick == 3
        end
      end

      it "opens with every app in one apps event" do
        expect(named("apps").map { it["apps"].map { |a| [a["process"], a["state"]] } }).to eq([[%w[api starting], %w[web starting]]])
      end

      it "sends one app event per process that changed, and stopped for each that went away" do
        expect(named("app").map { [it["process"], it["state"]] }).to eq([%w[api ready], %w[web ready], %w[api stopped], %w[web stopped]])
      end
    end

    context "when no app is running" do
      before { run_ticks }

      it "sends nothing about apps, so the stream is the one it always was" do
        expect(frames.grep(/event: apps?\n/)).to be_empty
      end
    end

    context "when the copilot conversation moves" do
      let(:copilot) { OpenLanes::Live.copilot(store:, keys:, responder: OpenLanes::Web::Demo::COPILOT) }
      let(:copilot_mark) { copilot.newest }

      before do
        copilot.answer(copilot.say({ "id" => "01JOLD", "text" => "before" }))
        copilot_mark
        run_ticks { |tick| copilot.answer(copilot.say({ "id" => "01JNEW", "text" => "after" })) if tick == 1 }
      end

      it "sends each new turn as a copilot event, leaving out what was said before it connected" do
        expect(frames.grep(/event: copilot\n/).map { JSON.parse(it[/data: (.*)$/, 1])["id"] }).to eq(%w[01JNEW 01JNEW.1])
      end

      it "names its boundary first: the newest turn when it opened, with no id of its own" do
        expect(frames[1]).to eq("event: copilot_cursor\ndata: #{JSON.generate(id: copilot_mark)}\n\n")
      end

      it "gives a copilot event no id, so the reply cursor stays where it was" do
        expect(frames.grep(/event: copilot\n/)).to all(start_with("event: copilot\n"))
      end
    end

    # The race the boundary closes: a turn written after the page's own
    # read but before the stream opened was in neither.
    context "when a turn lands just before the stream opens" do
      let(:copilot) { OpenLanes::Live.copilot(store:, keys:, responder: OpenLanes::Web::Demo::COPILOT) }

      before do
        copilot.answer(copilot.say({ "id" => "01JGAP", "text" => "in the gap" }))
        run_ticks
      end

      it "puts it at or before the boundary, which the page reads only once the stream says where that is" do
        boundary = JSON.parse(frames[1][/data: (.*)$/, 1])["id"]
        expect([boundary, copilot.since(boundary)]).to eq([copilot.newest, []])
      end
    end

    context "when the page is in a chat" do
      let(:page) { "page-0001" }
      let(:chat) { context.chat }

      before do
        chat.step
        run_ticks do |tick|
          chat.start_chat(page:, name: "Pat", machine: "1" * 24, label: "kim@x") if tick == 1
          chat.step
        end
      end

      it "opens with a chat cursor once the page is attached" do
        expect(frames.map { it[/event: (\w+)/, 1] }.compact.first(3)).to eq(%w[cursor copilot_cursor chat_cursor])
      end

      it "relays the chat's events as chat events with no id" do
        expect(frames.grep(/event: chat\n/).map { JSON.parse(it[/data: (.*)$/, 1])["kind"] }).to eq(%w[unanswered joined])
      end

      it "counts the page as gone once its stream ends" do
        expect(chat.instance_variable_get(:@pages)[page].streams).to eq(0)
      end
    end

    context "with a page id that is not one" do
      let(:page) { "../../x" }

      before { run_ticks }

      it "relays no chat" do
        expect(frames.grep(/event: chat\n/)).to be_empty
      end
    end

    context "when another node appears" do
      before do
        run_ticks { |tick| publish(1, node: "cccc:dddd") if tick == 1 }
      end

      it "sends the board again" do
        expect(frames.grep(/\Aevent: board/).last).to include("cccc:dddd")
      end
    end

    context "with a Last-Event-ID" do
      let(:last_id) { store.xadd(keys.replies, { json: '{"id":"01SEEN"}' }) }

      before do
        last_id
        reply("01MISSED")
        run_ticks
      end

      it "sends what came after it" do
        expect(frames.grep(/event: reply/).map { it[/"id":"(\w+)"/, 1] }).to eq(["01MISSED"])
      end

      it "opens with a cursor at the id the browser sent" do
        expect(opening).to start_with("id: #{last_id}\nevent: cursor\n")
      end
    end

    context "with a Last-Event-ID that is not a stream id" do
      let(:last_id) { "garbage" }

      before do
        reply("01BEFORE")
        run_ticks
      end

      it "starts from now" do
        expect(frames.grep(/event: reply/)).to be_empty
      end
    end

    context "when the browser leaves" do
      let(:out) { out_class.new { |_, stream| stream.close } }
      let(:lifetime) { nil }

      before { run_ticks }

      it "stops after the write it noticed on" do
        expect(frames).to eq([opening])
      end
    end

    context "when the server stops" do
      let(:lifetime) { nil }

      before { run_ticks { context.stopping.make_true } }

      it "ends within a tick" do
        expect(frames.grep(/\Aevent: board/).size).to eq(1)
      end
    end

    context "when Redis goes away" do
      before do
        allow(store).to receive(:get).and_raise(OpenLanes::Live::Unavailable, "Redis at x is unavailable")
        run_ticks
      end

      it "says so in a comment and ends, for the page to reconnect" do
        expect(frames.drop(2)).to eq([": Redis at x is unavailable\n\n"])
      end
    end
  end
end

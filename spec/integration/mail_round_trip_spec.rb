# frozen_string_literal: true

require "json"
require "open3"
require "rack/test"
require_relative "../openlanes/live/live_context"

# Plan 003, F2: one message's whole life, through the real pieces. The CLI
# runs as `exe/openlanes` in its own process; the dispatcher, the board, the
# snapshot and the web app are the real ones, over the in-memory store. The
# agents are the held fakes from the live context, so no coding CLI starts.
RSpec.describe "Mail round trip", :tree do
  include Rack::Test::Methods

  include_context "with a live run"

  let(:exe) { File.expand_path("../../exe/openlanes", __dir__) }
  let(:folder) { path_of("001.00") }
  let(:state) { OpenLanes::Plans::PlanState.for(folder) }
  let(:mail) { OpenLanes::Live::Mail.new(store:, keys:) }
  let(:context) do
    OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store),
      keys:,
      plans_dir: plans_root,
      url: "memory://",
      dist: plans_root,
      node:,
      lifetime: 0.2,
      copilot: OpenLanes::Web::Demo::COPILOT,
      background: ->(&) {})
  end
  let(:app) { OpenLanes::Web.app(context) }

  # `exe/openlanes`, with Redis pointed at a port nothing listens on, so a
  # send takes the no-Redis path whatever runs on this machine's 6379.
  def openlanes(*args)
    env = { "NO_COLOR" => "1", "REDIS_URL" => "redis://127.0.0.1:1/0", "OPENLANES_REDIS_URL" => nil }
    out, err, status = Open3.capture3(env, exe, *args, chdir: File.dirname(plans_root))
    raise "openlanes #{args.join(" ")} failed: #{err}" unless status.success?

    out
  end

  # What the page is given: the snapshot as the publisher writes it, read
  # back through the web app's own route.
  def page_plan(ordinal = "001.00", board: dispatcher.board)
    data = OpenLanes::Live::Snapshot.new(board:,
      tree: tree.reload,
      agents:,
      node:,
      repo: keys.repo,
      project: "openlanes",
      seq: 1,
      claims:,
      run_state:).to_h
    store.set(keys.snapshot, JSON.generate(data))
    header "Host", "127.0.0.1:11000"
    get "/api/board"
    JSON.parse(last_response.body).dig("me", "plans").find { it["ordinal"] == ordinal }
  end

  def board_unacked = dispatcher.board.rows.select { it.ordinal == "001.00" }.map(&:unacked).uniq

  # Every file in the folder with its bytes, so "unchanged" means unchanged.
  def folder_bytes = Dir.glob(File.join(folder, "**", "*")).select { File.file?(it) }.sort.to_h { [it, File.binread(it)] }

  def send_mail(body) = openlanes("mail", "send", "--dir", plans_root, "--plan", "001", *%w[--from luke-backend --to rey-frontend], body)

  def ack(number) = openlanes("mail", "ack", "--dir", plans_root, "--plan", "001", "--for", "rey-frontend", number.to_s)

  def render_mail = openlanes("mail", "render", "--dir", plans_root, "--plan", "001")

  def scoped_runner(ordinal, executor)
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :shared,
      jobs: 1,
      plans: [OpenLanes::Plans::Ordinal.parse(ordinal)],
      sleeper: ->(_) {})
  end

  # The agents one tick assigns to +ordinal+, on its own runner, so one
  # plan's round cannot crowd out the other's.
  def first_assignments(ordinal)
    held = HeldExecutor.new(traces)
    first = OpenLanes::Engine::Dispatcher.new(runner: scoped_runner(ordinal, held), sleeper: ->(_) {})
    first.tick
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    sleep(0.01) until held.calls.size >= first.running.size || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    held.calls.map { it.split("/").last }.sort
  ensure
    held&.release_all
    first&.running&.each { it.thread.join(2) }
  end

  # A board holding +ordinal+ and no rows: the page after its run ended.
  def idle_board(ordinal)
    OpenLanes::Engine::Board.new(started_at: 0,
      status: :idle,
      plans: [ordinal],
      up: 0,
      down: 0,
      rows: [],
      root: File.dirname(plans_root),
      running: 0,
      live_up: 0,
      live_down: 0)
  end

  before do
    building("001.00", "mail-round-trip")
    dispatcher.mail = mail
  end

  context "when the pair is running" do
    before { start_agents }

    it "shows one unread message after a send, however many ticks drain it" do
      send_mail("contract is up")
      # The same message reaches Redis too, as a send with Redis would
      # publish it; the drain must not keep it twice.
      mail.publish(plan: "001.00", message: state.messages.first)
      2.times { dispatcher.tick }

      aggregate_failures do
        expect(state.messages).to contain_exactly(include("number" => 1, "read" => "no", "to" => "rey-frontend"))
        expect(board_unacked).to eq([1])
        expect(page_plan).to include("unacked" => 1)
      end
    end

    it "shows nothing unread once the recipient acks" do
      send_mail("contract is up")
      ack(1)
      dispatcher.tick

      aggregate_failures do
        expect(state.messages.first).to include("read" => "yes")
        expect(board_unacked).to eq([0])
        expect(page_plan).to include("unacked" => 0)
      end
    end

    it "renders the exchange on STDOUT and leaves the folder byte for byte as it was" do
      send_mail("contract is up")
      ack(1)
      before = folder_bytes

      aggregate_failures do
        expect(render_mail).to include("luke-backend → rey-frontend", "read", "contract is up")
        expect(folder_bytes).to eq(before)
      end
    end

    it "keeps a message that only Redis carried, once" do
      mail.publish(plan: "001.00",
        message: { "number" => 1, "at" => "2026-10-14T10:00:00-07:00",
                                                      "from" => "luke-backend", "to" => "rey-frontend", "body" => "contract is up" })
      3.times { dispatcher.tick }

      expect([state.messages.size, page_plan["unacked"]]).to eq([1, 1])
    end
  end

  # Unacked mail is a warning on the screen, never an input to a round: a
  # plan with mail waiting gets exactly the agents one without it gets.
  it "assigns the same agents whether or not mail is waiting" do
    building("002.00", "with-mail")
    OpenLanes::Plans.mailbox(path_of("002.00")).append(from: "luke-backend", to: "rey-frontend", body: "unread")
    without, with = first_assignments("001.00"), first_assignments("002.00")

    aggregate_failures do
      expect(OpenLanes::Plans.mailbox(path_of("002.00")).unacked).to eq(1)
      expect(with).not_to be_empty
      expect(with).to eq(without)
    end
  end

  # A real round whose agent dies without `state resume`: the harness
  # writes the record, and the page shows it as the harness's.
  it "shows the page a harness resume record for an agent that died without leaving one" do
    building("002.00", "cut-off")
    scoped_runner("002.00", ->(*, **) { raise "adapter went away" }).call

    expect(page_plan("002.00", board: idle_board("002.00"))["last_known"])
      .to include(include("agent" => "luke-backend",
        "source" => "harness",
        "status" => "Interrupted",
        "note" => start_with("adapter went away")))
  end
end

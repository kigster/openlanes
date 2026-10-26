# frozen_string_literal: true

require "open3"
require "rack/test"

# Plan 009.00 end to end. A real `.plans` tree, the real executable, the real
# control-room app taking commands over HTTP, and the engine's own command
# reader applying them. Nothing is stubbed but the agent process: the drainer
# is an executor that retires blocked.md the way unblocker would, and the
# `claude`, `codex` and `pi` on PATH are scripts that fail if anything calls
# them. GitHub is never reached: the run is `--isolation shared`.
RSpec.describe "plan aging and bombs, end to end", :tree do
  include Rack::Test::Methods

  let(:exe) { File.expand_path("../../../exe/openlanes", __dir__) }
  let(:project) { File.dirname(plans_root) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }

  let(:store) { OpenLanes::Live.memory_store }
  let(:node) do
    OpenLanes::Live::Node.new(id: "aaaa", user: "pat", host: "box", ip: nil, checkout: "~/widgets", checkout_id: "bbbb")
  end
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: node.name) }
  let(:context) do
    OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store),
      keys:,
      plans_dir: plans_root,
      url: "redis://localhost:6379/12",
      dist: project,
      node:,
      lifetime: 0.2,
      copilot: OpenLanes::Web::Demo::COPILOT,
      background: ->(&work) { work })
  end
  let(:app) { OpenLanes::Web.app(context) }
  let(:run_state) { OpenLanes::Live::RunState.new }
  let(:commands) { OpenLanes::Live::Commands.new(store:, keys:, node:, run_state:) }

  # The drainer's stand-in: it folds every answer by retiring blocked.md.
  let(:executor) do
    lambda { |_agent, subject, **|
      File.delete(File.join(subject.feature.path, "blocked.md"))
      OpenLanes::Execution::Executor::Result.new(ok: true, note: "folded", up: 0, down: 0, subagents: 0, delegated: 0, seconds: 0.0)
    }
  end
  let(:runner) { OpenLanes::Engine::Runner.new(tree:, executor:, isolation: :shared, sleeper: ->(_) {}) }
  let(:dispatcher) { OpenLanes::Engine::Dispatcher.new(runner:, sleeper: ->(_) {}) }

  # Agents that must never run: each fails loudly if invoked.
  let(:guard) do
    File.join(project, "nobin").tap do |dir|
      FileUtils.mkdir_p(dir)
      %w[claude codex pi].each do |name|
        File.write(File.join(dir, name), "#!/bin/sh\necho \"#{name} must not run in this spec\" >&2\nexit 97\n")
        File.chmod(0o755, File.join(dir, name))
      end
    end
  end

  let(:question) { "## B1 Which feed?\n\nVendor or ours?\n" }

  def needs(*ordinals) = "---\ndepends_on: #{ordinals.inspect}\n---\n#{spec_body}"

  def blocked(ordinal, slug, days:)
    path = nil
    plans do |t|
      path = t.plan ordinal,
        :blocked,
        slug,
        files: { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## U1\n", "blocked.md" => question }
    end
    OpenLanes::Plans::PlanState.for(path).sign!(agent: "backend-coder", round: 1, status: "Blocked", at: Time.now - (days * 86_400))
  end

  def waiting_on(ordinal, slug, on)
    plans do |t|
      t.plan ordinal, :building, slug, files: { "spec.md" => needs(on), "plan.md" => "# Plan\n\n## U1\n", "plan-frontend.md" => "## F1\n" }
    end
  end

  def openlanes(*)
    env = { "NO_COLOR" => "1", "PATH" => "#{guard}:#{ENV.fetch("PATH")}", "REDIS_URL" => "redis://127.0.0.1:1" }
    out, status = Open3.capture2e(env, exe, *, "--dir", plans_root, chdir: project)
    [strip_ansi(out), status.exitstatus]
  end

  def snapshot
    board = OpenLanes::Engine::Board.new(started_at: 0,
      status: :running,
      plans: [],
      up: 0,
      down: 0,
      rows: [],
      root: project,
      running: 0,
      live_up: 0,
      live_down: 0)
    OpenLanes::Live::Snapshot.new(board:,
      tree:,
      agents: runner.agents,
      node:,
      repo: keys.repo,
      project: "widgets",
      seq: 1,
      run_state:).to_h
  end

  def post_command(kind, plan, **payload)
    header "Host", "127.0.0.1:11000"
    header "X-CSRF-Token", context.csrf
    post "/api/commands",
      JSON.generate(id: "01J#{kind.upcase.delete("_")}", kind:, plan:, agent: nil, payload:),
      "CONTENT_TYPE" => "application/json"
    expect(last_response.status).to eq(202)
    commands.call(dispatcher)
  end

  def status_of(ordinal) = tree.reload.find(ordinal).status.key

  before do
    system("git", "init", "-q", project, exception: true)
    blocked("001.00", "feed", days: 8)
    waiting_on("002.00", "consumer", "001.00")
    blocked("003.00", "ports", days: 8)
    waiting_on("004.00", "stacks", "003.00")
  end

  after { OpenLanes::Execution::Control.reset! }

  # 1. The run bombs both plans, starts nobody, exits 1 and names them.
  def expect_halted_run
    out, status = openlanes("run", "--isolation", "shared", "--no-web")
    expect(status).to eq(1)
    expect(out).to include("Halted", "001.00 Feed", "003.00 Ports")
    expect(out).not_to include("must not run")
    expect([status_of("001.00"), status_of("003.00")]).to eq(%i[bomb bomb])
  end

  # 4. The next round drains it: 001 leaves 💣 and the snapshot, while 003 still halts the run.
  def expect_drained
    dispatcher.tick
    dispatcher.instance_variable_get(:@unblocking).each { it.thread.join(5) }
    dispatcher.tick
    expect(status_of("001.00")).not_to eq(:bomb)
    expect(snapshot[:bombs].map { it[:plan] }).to eq(%w[003.00])
    expect(runner.halted_by.map { it.feature.ordinal.to_s }).to eq(%w[003.00])
  end

  it "halts on the 💣, answers it over HTTP, drains it, and lifts a second halt for a day" do
    aggregate_failures do
      expect_halted_run

      # 2. The snapshot lists both, with their blocked.md.
      expect(snapshot[:bombs].map { [it[:plan], it[:blocked_md]] }).to eq([["001.00", question], ["003.00", question]])

      # 3. Respond, posted to the control room, lands in blocked.md.
      post_command("respond", "001.00", text: "The vendor's feed.")
      expect(File.read(File.join(tree.reload.find("001.00").feature.path, "blocked.md")))
        .to include("## A1\n\nThe vendor's feed.\n\nAnswered by pat on")

      expect_drained

      # 5. Resume anyway lifts 003's halt for a day, with no config edit.
      post_command("resume_anyway", "003.00")
      expect(runner).not_to be_halted
      expect(snapshot[:bombs].first[:resume_until]).not_to be_nil
      expect(File.exist?(File.join(project, ".openlanes.yml"))).to be(false)
    end
  end
end

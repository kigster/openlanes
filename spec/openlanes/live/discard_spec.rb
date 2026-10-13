# frozen_string_literal: true

require "open3"
require_relative "live_context"

# W9's discard, end to end over a real git repository: the page's command
# stops every agent on the plan, resets the plan's own worktree, sends the
# folder back one state, and only then answers.
RSpec.describe "Discarding a plan", :tree do
  subject(:commands) do
    OpenLanes::Live::Commands.new(store:, keys:, node:, run_state:, claims:, clock: -> { Time.utc(2026, 10, 13, 9) })
  end

  include_context "with a live run"

  let(:root) { File.dirname(plans_root) }
  let(:worktrees) { OpenLanes::Vcs::Worktree.new(root:, dir: "#{root}.worktrees", user: "tester") }
  let(:runner) do
    OpenLanes::Engine::Runner.new(tree:,
      executor:,
      agents:,
      isolation: :worktree,
      jobs: 2,
      worktree: worktrees,
      claims:,
      sleeper: ->(_) {})
  end
  let(:checkout) { worktrees.path_for(tree.reload.find("001.00").feature) }

  def git(*) = Open3.capture2e("git", "-C", root, *)

  def send_discard(id = "01JD")
    OpenLanes::Live.enqueue(store:, keys:, input: { id:, kind: "discard", plan: "001.00", payload: {} })
  end

  def reply_to(id) = store.hget(keys.done, id)&.then { JSON.parse(it) }

  before do
    stub_const("OpenLanes::Engine::Dispatcher::KILL_GRACE", 0)
    allow(OpenLanes::UI).to receive(:log)
    git("init", "-q", "--initial-branch=main")
    git("config", "user.email", "dana@example.test")
    git("config", "user.name", "Dana Example")
    File.write(File.join(root, "app.rb"), "puts :ok\n")
    git("add", "app.rb")
    git("commit", "-qm", "initial")
    building("001.00", "tax-rule-dsl")
    start_agents
    File.write(File.join(checkout, "app.rb"), "puts :half_done\n")
    File.write(File.join(checkout, "scratch.rb"), "1\n")
    send_discard
    dispatcher.before_tick(&commands)
    dispatcher.tick
  end

  after { FileUtils.rm_rf("#{root}.worktrees") }

  it "does not answer while the plan's agents are still stopping" do
    aggregate_failures do
      expect(reply_to("01JD")).to be_nil
      expect(dispatcher.running.map { it.handle.killed }.uniq).to eq([:discard])
      expect(dispatcher).not_to be_done
    end
  end

  context "when every agent has stopped" do
    before do
      executor.release_all
      dispatcher.running.each { it.thread.join(2) }
      2.times { dispatcher.tick }
    end

    it "resets the worktree, sends the plan back one state, answers done, and starts it again from there" do
      aggregate_failures do
        expect(reply_to("01JD")).to include("status" => "done",
          "reason" => "001.00 reset, and went back from 🟡 Building to ⭐️ Planned")
        expect(File.read(File.join(checkout, "app.rb"))).to eq("puts :ok\n")
        expect(File.exist?(File.join(checkout, "scratch.rb"))).to be(false)
        expect(executor.calls.size).to be > 2
      end
    end

    it "signs nothing for the stopped agents" do
      expect(dispatcher.attempts.map { [it.ok, it.note] }.uniq).to eq([[false, "discarded by a person"]])
    end
  end

  context "when the folder cannot go back" do
    before do
      File.write(File.join(tree.reload.find("001.00").feature.path, "pull-requests.md"),
        "| Pull Request Number | Pull Request Name | Status |\n| --: | :-- | --: |\n| 7 | [Rules](https://github.com/example/repo/pull/7) | Open 🟡 |\n")
      executor.release_all
      dispatcher.running.each { it.thread.join(2) }
      2.times { dispatcher.tick }
    end

    it "is refused, saying the agents were stopped and why the move was not made" do
      expect(reply_to("01JD")).to include("status" => "refused",
        "reason" => a_string_starting_with("001.00's agents were stopped, but:"))
    end
  end
end

# frozen_string_literal: true

require_relative "../live/live_context"

# W31: a plan somebody outside openlanes holds in alock is stepped around,
# and one the engine loses to them at the last moment is left exactly as it
# was: not renamed, not claimed from other machines, never started.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  # alock as the dispatcher sees it: who holds which folder, and who would
  # win a race for one the listing still showed free.
  let(:outside) do
    Class.new do
      def initialize = (@held, @lost, @acquired, @released = [], [], [], [])

      attr_reader :held, :lost, :acquired, :released

      def held_elsewhere(dir, **)
        "claude-1 (refactoring)" if @held.any? { File.basename(dir).start_with?(it) }
      end

      def acquire(dir, _intent)
        return false if @lost.any? { File.basename(dir).start_with?(it) }

        @acquired << File.basename(dir)
        true
      end

      def release(dir) = @released << File.basename(dir)
    end.new
  end

  def planned(ordinal, slug)
    plans { |t| t.plan ordinal, :planned, slug, files: { "spec.md" => spec_body, "plan.md" => "# Plan\n\n## Unit 1\n" } }
  end

  def folder(ordinal) = File.basename(path_of(ordinal))

  before do
    OpenLanes::Engine.agent_locks = ->(_) { outside }
    planned("001.00", "held")
    planned("002.00", "lost")
    planned("003.00", "free")
  end

  it "starts only the plan nobody outside openlanes holds" do
    outside.held << "001.00"
    outside.lost << "002.00"
    start_agents

    aggregate_failures do
      expect(executor.calls.map { it.split("/").first }.uniq).to eq(["003.00"])
      expect(folder("003.00")).to include("🟡")
      expect(outside.acquired.last).to include("003.00━━🟡")
    end
  end

  it "leaves a plan it lost at the last moment as it was, and gives its claim back" do
    outside.lost << "002.00"
    before = folder("002.00")
    start_agents

    aggregate_failures do
      expect(folder("002.00")).to eq(before)
      expect(claims.held_by("002.00")).to be_nil
      expect(executor.calls).not_to include(a_string_starting_with("002.00"))
    end
  end

  it "treats a held plan as untouchable, so nothing renames it either" do
    outside.held << "001.00"

    expect(dispatcher.send(:untouchable)).to include("001.00")
  end

  it "gives the folder back when the last agent in the plan finishes" do
    start_agents
    executor.release_all
    dispatcher.running.each { it.thread.join(2) }

    expect(outside.released).to include(a_string_starting_with("001.00"))
  end
end

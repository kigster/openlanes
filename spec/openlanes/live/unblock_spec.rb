# frozen_string_literal: true

require_relative "live_context"

# An answer from the page has to actually unblock the plan: once every
# question has one, the run hands the plan to the agent that handles its
# state, as `openlanes unblock` would, and picks it up again afterwards.
RSpec.describe "Unblocking from the run loop", :tree do
  include_context "with a live run"

  # Stands in for every agent: the one that drains blocked.md retires the
  # file, as lando-broker does once the last question folds in; anyone else
  # finishes at once.
  let(:executor) do
    Class.new do
      def initialize = @calls = []

      attr_reader :calls

      def call(agent, subject, **)
        @calls << "#{subject.feature.ordinal}/#{agent.name}"
        if agent.name == "lando-broker" && @refuse
          OpenLanes::Plans::PlanState.for(subject.feature.path)
                                     .journal!(agent: agent.name, entries: [OpenLanes::Plans::Journal::Entry.new(kind: "note", text: @refuse)])
        elsif agent.name == "lando-broker" && !@fail
          File.delete(File.join(subject.feature.path, "blocked.md"))
        end
        OpenLanes::Execution::Executor::Result.new(ok: !@fail,
          note: "completed",
          up: 1,
          down: 1,
          subagents: 0,
          delegated: 0,
          seconds: 0.1)
      end

      def fail! = @fail = true

      def refuse!(why) = @refuse = why
    end.new
  end

  let(:answered) { "## B1 Rebase\n\nShould I?\n\n## A1\n\nyes\n\nAnswered by dana on 2026-10-13\n" }

  def drain
    dispatcher.tick
    dispatcher.instance_variable_get(:@unblocking).each { it.thread.join(2) }
    # The agent the second tick starts records its call on its own thread, a
    # moment later; under a loaded suite the assertion could run first.
    start_agents
  end

  before { allow(OpenLanes::UI).to receive(:log) }

  context "with every question answered" do
    before do
      blocked("002.00", "rebase", answered)
      drain
    end

    it "hands the plan to lando-broker, and the next round renames it and starts it again" do
      aggregate_failures do
        expect(executor.calls.first).to eq("002.00/lando-broker")
        expect(tree.reload.find("002.00").status.key).not_to eq(:blocked)
        expect(executor.calls.size).to be > 1
      end
    end
  end

  context "with a question still open" do
    before do
      blocked("002.00", "rebase", "#{answered}\n## B2 Squash\n\nShould I?\n")
      drain
    end

    it "leaves the plan waiting for a person" do
      expect([executor.calls, tree.reload.find("002.00").status.key]).to eq([[], :blocked])
    end
  end

  context "when the drain fails" do
    before do
      executor.fail!
      blocked("002.00", "rebase", answered)
      drain
      drain
    end

    it "tries once, and waits for blocked.md to change before trying again" do
      aggregate_failures do
        expect(executor.calls).to eq(%w[002.00/lando-broker])
        expect(OpenLanes::UI).to have_received(:log).with("unblock failed: completed", level: :warn, plan: "002.00")
        expect(dispatcher.send(:idle_reason, runner.in_scope))
          .to eq("idle: unblock failed on 002.00 (completed); edit blocked.md to try again")
      end
    end
  end

  context "when the broker will not take the answer" do
    before do
      executor.refuse!("'yes' names none of a/b/c; not an answer")
      blocked("002.00", "rebase", answered)
      drain
    end

    let(:file) { File.read(File.join(tree.reload.find("002.00").feature.path, "blocked.md")) }

    it "puts the question back on the page, saying what was refused and why" do
      aggregate_failures do
        expect(file).not_to match(/^## A1/)
        expect(file).to include("> **Answer not accepted:** yes", "lando-broker: 'yes' names none of a/b/c")
        expect(OpenLanes::Lifecycle::Unblocker.questions(tree.find("002.00")).map(&:answered)).to eq([false])
      end
    end

    it "logs which answer was refused, and why" do
      expect(OpenLanes::UI).to have_received(:log)
        .with("answer to B1 not accepted: lando-broker: 'yes' names none of a/b/c; not an answer", level: :warn, plan: "002.00")
    end
  end

  context "when another machine holds the plan" do
    before do
      blocked("002.00", "rebase", answered)
      store.set(keys.claim("002.00"), "ffffffffffffffffffffffff:000000000000")
      drain
    end

    it "leaves it to that machine" do
      expect(executor.calls).to eq([])
    end
  end
end

# frozen_string_literal: true

require_relative "../live/live_context"

# While the round is still running: a round killed later keeps what it
# printed before the kill.
RSpec.describe OpenLanes::Engine::Dispatcher, :tree do
  include_context "with a live run"

  let(:job) { dispatcher.running.first }
  let(:journal) { OpenLanes::Plans::Journal }
  let(:entries) { OpenLanes::Plans::PlanState.for(path_of("001.00")).journal(job.task.agent.name).flat_map(&:entries) }

  before do
    building("001.00", "tax-rule-dsl")
    start_agents
    job.journal = journal.scan(journal.line("decision", "Integer cents"))
    dispatcher.tick
  end

  it "writes an entry on the tick after it was printed" do
    expect(entries.map(&:text)).to eq(["Integer cents"])
  end

  it "does not write it twice on the next tick" do
    job.journal += journal.scan(journal.line("done", "U1"))
    dispatcher.tick
    expect(entries.map(&:text)).to eq(["Integer cents", "U1"])
  end

  # A write that fails must not move the place in the list past the lines
  # it failed to write, or the agent's journal has a hole it never sees.
  context "when state.json cannot be read for one tick" do
    let(:heard) { [] }
    let!(:tap) { OpenLanes::UI.tap_log(->(message, _) { heard << message }) }

    before do
      path = OpenLanes::Plans::PlanState.for(path_of("001.00")).path
      kept = File.read(path)
      job.journal += journal.scan(journal.line("done", "U1"))
      File.write(path, "{")
      dispatcher.tick
      File.write(path, kept)
      dispatcher.tick
    end

    after { OpenLanes::UI.untap_log(tap) }

    it "writes the lines on the next tick that can" do
      expect(entries.map(&:text)).to eq(["Integer cents", "U1"])
    end

    it "says it could not write them yet" do
      expect(heard.grep(/journal not written yet/)).not_to be_empty
    end
  end

  context "when the plan folder is not found for one tick" do
    before do
      folder = path_of("001.00")
      aside = "#{File.dirname(plans_root)}/aside"
      job.journal += journal.scan(journal.line("done", "U1"))
      FileUtils.mv(folder, aside)
      record_journal
      FileUtils.mv(aside, folder)
      record_journal
    end

    def record_journal = dispatcher.send(:record_journal, job)

    it "writes the lines once it is back" do
      expect(entries.map(&:text)).to eq(["Integer cents", "U1"])
    end
  end
end

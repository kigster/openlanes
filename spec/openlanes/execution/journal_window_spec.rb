# frozen_string_literal: true

# Plan 062.00: a round that resumes a session is sent only the journal
# entries that session does not already hold, and the whole journal whenever
# what it holds is in doubt.
RSpec.describe OpenLanes::Execution::JournalWindow, :tree do
  subject(:window) { described_class.for(state, agent: "backend-coder", resume:) }

  let(:state) do
    path = nil
    plans { |t| path = t.plan "001.00", :building, "work", files: { "spec.md" => spec_body, "plan.md" => "## U1" } }
    OpenLanes::Plans::PlanState.for(path)
  end
  let(:entry) { OpenLanes::Plans::Journal::Entry }
  let(:resume) { "sess-1" }

  def note(*texts) = state.journal!(agent: "backend-coder", entries: texts.map { entry.new(kind: "note", text: it) })

  def texts = window.entries.map { |_, number, e| [number, e.text] }

  before { note("one", "two") }

  context "when the resumed session holds the journal so far" do
    before do
      state.hold!(agent: "backend-coder", session: "sess-1")
      note("three")
    end

    it "carries only the entries written since, under their own numbers" do
      expect([window.resumed?, window.since, texts, window.total]).to eq([true, 2, [[3, "three"]], 3])
    end

    it "still numbers the whole journal, for the overrides" do
      expect(window.numbered.map { |_, number, _| number }).to eq([1, 2, 3])
    end
  end

  context "when nothing was written since" do
    before { state.hold!(agent: "backend-coder", session: "sess-1") }

    it "carries no entry" do
      expect([window.resumed?, texts]).to eq([true, []])
    end
  end

  context "when the round starts a fresh session" do
    let(:resume) { nil }

    before { state.hold!(agent: "backend-coder", session: "sess-1") }

    it "carries the whole journal" do
      expect([window.resumed?, texts]).to eq([false, [[1, "one"], [2, "two"]]])
    end
  end

  context "when no round recorded what the session holds" do
    it "carries the whole journal" do
      expect([window.resumed?, texts.size]).to eq([false, 2])
    end
  end

  context "when the record is another session's" do
    before { state.hold!(agent: "backend-coder", session: "sess-0") }

    it "carries the whole journal" do
      expect([window.resumed?, texts.size]).to eq([false, 2])
    end
  end

  context "when the record was forgotten, as a round that starts does" do
    before do
      state.hold!(agent: "backend-coder", session: "sess-1")
      state.forget_held!("backend-coder")
    end

    it "carries the whole journal" do
      expect([window.resumed?, texts.size]).to eq([false, 2])
    end
  end

  context "when the record counts more entries than the journal has" do
    let(:held) { OpenLanes::Plans::Journal::Held.new(session: "sess-1", through: 9) }

    it "is not believed" do
      expect(described_class.new(rounds: state.journal("backend-coder"), held:, resume:).resumed?).to be(false)
    end
  end

  context "when another agent's session holds its own journal" do
    before { state.hold!(agent: "frontend-coder", session: "sess-1") }

    it "carries the whole journal" do
      expect(window.resumed?).to be(false)
    end
  end
end

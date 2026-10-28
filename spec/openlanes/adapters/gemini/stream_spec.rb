# frozen_string_literal: true

# Fixtures built from gemini 0.51.0's source: the account this was written on
# is refused, so there is no recorded run yet (plan 040, D21).
RSpec.describe OpenLanes::Adapters::Gemini::Stream do
  subject(:stream) { described_class.new { |progress| seen << progress } }

  let(:seen) { [] }
  let(:fixture) { "gemini-read" }
  let(:lines) { File.read(File.expand_path("../../../fixtures/streams/#{fixture}.ndjson", __dir__)) }

  before do
    lines.chars.each_slice(61) { |chunk| stream.push(chunk.join) }
    stream.finish
  end

  context "with a run that reads a file and is refused a push" do
    it "meters the result's stats, whose input already counts the cached part" do
      expect([stream.up, stream.down, stream.cached]).to eq([9800, 210, 6000])
    end

    it "counts both tool calls" do
      expect(stream.tools).to eq(2)
    end

    it "keeps the last whole message, not the user's prompt or a fragment" do
      expect(stream.result).to eq("The note says hello.")
    end

    it "names the session from the start" do
      expect([stream.session, seen.first.session]).to eq(%w[5d0c1e2a-6f0b-4a51-9a8e-1c2d3e4f5a6b] * 2)
    end

    it "does not fail on a warning or a refused command" do
      expect(stream.failed?).to be(false)
    end
  end

  context "with a run that ended in an error" do
    let(:fixture) { "gemini-failed" }

    it { expect(stream.error).to eq("Reached max session turns for this session.") }
    it { expect([stream.up, stream.down]).to eq([1000, 200]) }
  end

  context "with an error-level event" do
    let(:lines) { %({"type":"error","severity":"error","message":"Maximum session turns exceeded"}\n) }

    it { expect(stream.error).to eq("Maximum session turns exceeded") }
  end

  context "with a result that is an error and says nothing more" do
    let(:lines) { %({"type":"result","status":"error"}\n) }

    it { expect(stream.error).to eq("gemini reported an error") }
  end

  context "with journal lines split across fragments" do
    let(:decision) { OpenLanes::Plans::Journal.line("decision", "Integer cents") }
    let(:lines) do
      [{ type: "message", role: "assistant", content: decision[0, 15], delta: true },
       { type: "message", role: "assistant", content: "#{decision[15..]}\n", delta: true },
       { type: "result", status: "success", stats: {} }].map { "#{JSON.generate(it)}\n" }.join
    end

    it "takes the line once" do
      expect(stream.journal.map(&:text)).to eq(["Integer cents"])
    end
  end
end

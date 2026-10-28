# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Grok::Stream do
  subject(:stream) { described_class.new(session:) { |progress| seen << progress } }

  let(:session) { nil }
  let(:seen) { [] }
  let(:fixture) { "grok-read" }
  let(:lines) { File.read(File.expand_path("../../../fixtures/streams/#{fixture}.ndjson", __dir__)) }

  before do
    lines.chars.each_slice(97) { |chunk| stream.push(chunk.join) }
    stream.finish
  end

  context "with a recorded run that reads one file" do
    it "meters every turn once, cached input included, and not the totals again" do
      expect([stream.up, stream.down, stream.cached]).to eq([48_287 + 2304 + 186 + 50_560, 143 + 17, 2304 + 50_560])
    end

    it "counts the tool call, not its updates" do
      expect(stream.tools).to eq(1)
    end

    it "keeps what the agent said, not what the tool returned" do
      expect([stream.result, stream.activity]).to eq(["The note says hello.", "The note says hello."])
    end

    it "takes the session grok confirms at the end" do
      expect([stream.session, seen.last.session]).to eq(%w[37dc7176-b9e6-425d-bdb4-95cd12b1194b] * 2)
    end

    it "is not an error, and nothing compacted" do
      expect([stream.failed?, stream.compacted]).to eq([false, nil])
    end
  end

  context "with a session already known from the argv" do
    let(:session) { "from-argv" }

    it "keeps it" do
      expect(seen.map(&:session).uniq).to eq(["from-argv"])
    end
  end

  context "with a command the denylist refused" do
    let(:fixture) { "grok-denied" }

    it "reads the refusal as the agent's answer, not as a failed run" do
      expect([stream.failed?, stream.result]).to match([false, a_string_starting_with("`git status --short` did not run.")])
    end
  end

  context "with /compact sent into a resumed session" do
    let(:fixture) { "grok-compact" }

    it { expect(stream.compacted).to eq({}) }
  end

  context "with an error" do
    let(:lines) do
      %({"type":"error","message":"--effort/--reasoning-effort: unknown effort level 'bogus'"}\n)
    end

    it { expect(stream.error).to eq("--effort/--reasoning-effort: unknown effort level 'bogus'") }
  end

  context "with journal lines across a tool call" do
    let(:todo) { OpenLanes::Plans::Journal.line("todo", "U1") }
    let(:done) { OpenLanes::Plans::Journal.line("done", "U1") }
    let(:lines) do
      [{ type: "text", data: todo[0, 20] }, { type: "text", data: "#{todo[20..]}\nstill thinking" },
       { type: "tool_call", toolName: "read_file" },
       { type: "text", data: done },
       { type: "end", sessionId: "s" }].map { "#{JSON.generate(it)}\n" }.join
    end

    it "takes each line once, whether finished mid-message or as the message closed" do
      expect(stream.journal.map(&:kind)).to eq(%w[todo done])
    end

    it "keeps the message after the tool call as the last thing said" do
      expect(stream.result).to eq(done)
    end
  end
end

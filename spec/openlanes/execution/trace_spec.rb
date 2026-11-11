# frozen_string_literal: true

RSpec.describe OpenLanes::Execution::Trace do
  let(:path) { File.join(Dir.mktmpdir, "trace.ndjson") }

  def write(*events) = File.write(path, events.map { "#{JSON.generate(it)}\n" }.join)

  it "reads the last result event's text" do
    write({ type: "assistant", message: {} }, { type: "result", result: "first" }, { type: "result", result: "Ruled." })

    expect(OpenLanes::Execution.answer(path)).to eq("Ruled.")
  end

  it "is empty when the trace has no result line" do
    write({ type: "assistant", message: {} })

    expect(described_class.answer(path)).to eq("")
  end

  it "is empty when there is no trace" do
    expect([described_class.answer(nil), described_class.answer(path)]).to eq(["", ""])
  end

  it "is empty when a result line is not JSON" do
    File.write(path, "{\"result\": \n")

    expect(described_class.answer(path)).to eq("")
  end
end

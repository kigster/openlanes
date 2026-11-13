# frozen_string_literal: true

RSpec.describe OpenLanes::Live::Copilot::RestartNote do
  subject(:note) { described_class.new(path:, copilot:) }

  let(:dir) { Dir.mktmpdir("restart-note") }
  let(:path) { File.join(dir, "web-restart.json") }
  let(:told) { [] }
  let(:copilot) { instance_double(OpenLanes::Live::Copilot).tap { |c| allow(c).to receive(:tell) { told << it } } }

  def leave(status, message) = File.write(path, JSON.generate(status:, message:, at: "2026-11-13T10:00:00Z"))

  after { FileUtils.rm_rf(dir) }

  it "tells a rebuilt page once, as the copilot, and removes the note" do
    leave("ok", "the page was rebuilt")
    2.times { note.call }
    aggregate_failures do
      expect(told.map(&:text)).to eq(["The control room restarted on a rebuilt page. The page was rebuilt."])
      expect(told.first).to have_attributes(from: "copilot", kind: "text", id: "web-restart-#{Time.utc(2026, 11, 13, 10).to_i}")
      expect(File.exist?(path)).to be(false)
    end
  end

  {
    "failed"     => "the build failed (exit 2), so the old page stays",
    "no_npm"     => "the page was not rebuilt: npm is not on PATH",
    "no_sources" => "the page was not rebuilt: /gem/web/package.json is missing",
    "timeout"    => "the build ran past 300 seconds and was stopped, so the old page stays"
  }.each do |status, message|
    it "tells #{status} with its reason" do
      leave(status, message)
      note.call
      expect(told.first.text).to start_with("The control room restarted on its old page.").and include(message[1..])
    end
  end

  it "does nothing when there is no note" do
    expect([note.call, told]).to eq([nil, []])
  end

  it "drops a note it cannot read" do
    File.write(path, "{")
    expect([note.call, told, File.exist?(path)]).to eq([nil, [], false])
  end
end

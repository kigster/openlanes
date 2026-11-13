# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::WebRestartNote do
  it "is taken, through the facade, from beside the project's PID files" do
    root = Dir.mktmpdir("restart-note-root")
    outcome = OpenLanes::Supervision::WebRebuild::Outcome.new(status: "ok", message: "the page was rebuilt")
    path = File.join(OpenLanes::Supervision.dir(root).path, OpenLanes::Supervision::WebRestart::NOTE)
    described_class.new(outcome:, at: Time.utc(2026, 11, 13, 10)).write(path)
    expect(OpenLanes::Supervision.take_restart_note(root)).to have_attributes(outcome:, at: Time.utc(2026, 11, 13, 10))
  ensure
    FileUtils.rm_rf(root)
  end
end

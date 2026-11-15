# frozen_string_literal: true

RSpec.describe OpenLanes::Supervision::WebRestartNote do
  let(:root) { Dir.mktmpdir("restart-note-root") }
  let(:path) { File.join(root, "pids", OpenLanes::Supervision::WebRestart::NOTE) }
  let(:at) { Time.utc(2026, 11, 13, 10) }
  let(:outcome) { OpenLanes::Supervision::WebRebuild::Outcome.new(status: "ok", message: "the page was rebuilt") }

  before { described_class.new(outcome:, at:).write(path) }

  after { FileUtils.rm_rf(root) }

  describe "through the facade" do
    let(:path) { File.join(OpenLanes::Supervision.dir(root).path, OpenLanes::Supervision::WebRestart::NOTE) }

    after { FileUtils.rm_f(path) }

    it "is taken from beside the project's PID files" do
      expect(OpenLanes::Supervision.take_restart_note(root, now: at + 5)).to have_attributes(outcome:, at:)
    end

    it "is told when read just now" do
      described_class.new(outcome:, at: Time.now).write(path)
      expect(OpenLanes::Supervision.take_restart_note(root)).to have_attributes(outcome:)
    end
  end

  # Issue 253: a web that never came back leaves its note, and the next
  # server to boot announced a restart from days before.
  it "is removed and not told once it is no longer news" do
    stale = at + described_class::STALE_AFTER + 1
    expect([described_class.take(path, now: stale), File.exist?(path)]).to eq([nil, false])
  end

  it "is not told when it cannot be read at all" do
    File.delete(path)
    FileUtils.mkdir_p(path)
    expect(described_class.take(path)).to be_nil
  end

  it("is dropped when nobody took it") { expect([described_class.drop(path), File.exist?(path)]).to eq([[path], false]) }

  context "when the locale is not UTF-8 and the build printed what it cannot read" do
    let(:outcome) { OpenLanes::Supervision::WebRebuild::Outcome.new(status: "failed", message: "the build failed:\n✗ Build failed") }

    around do |example|
      external = Encoding.default_external
      verbose = $VERBOSE
      $VERBOSE = nil
      Encoding.default_external = Encoding::US_ASCII
      example.run
    ensure
      Encoding.default_external = external
      $VERBOSE = verbose
    end

    it("is still told") { expect(described_class.take(path, now: at)).to have_attributes(outcome:) }
  end
end

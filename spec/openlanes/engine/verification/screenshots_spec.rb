# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Verification::Screenshots do
  let(:dir) { Dir.mktmpdir("openlanes-screenshots") }
  let(:fixture) { File.expand_path("../../../fixtures/verification/step.png", __dir__) }
  let(:ran) { [] }
  # Stand-ins for vips and magick: what is under test is which file is kept,
  # not either tool's compression.
  let(:tools) do
    { "small" => ->(from, to) { ["small", from, to] }, "large" => ->(from, to) { ["large", from, to] } }
  end
  let(:runner) do
    lambda { |argv|
      ran << argv
      name, from, to = argv
      File.binwrite(to, name == "small" ? File.binread(from).byteslice(0, 100) : File.binread(from) * 2)
      true
    }
  end

  after { FileUtils.rm_rf(dir) }

  def put(name) = FileUtils.cp(fixture, File.join(dir, name))

  def screenshots(which: ->(_) { true }) = described_class.new(dir:, tools:, which:, runner:)

  it "keeps only the failing step and the final state" do
    %w[step-01.png step-02.png step-03.png final.png].each { put(it) }
    File.write(File.join(dir, "report.md"), "Verdict: rejected\n")

    kept = screenshots.prepare(failing_step: 2)

    aggregate_failures do
      expect(kept.map { File.basename(it) }).to eq(%w[step-02.png final.png])
      expect(Dir.children(dir).sort).to eq(%w[final.png report.md step-02.png])
    end
  end

  it "keeps only final.png when nothing failed" do
    %w[step-01.png final.png].each { put(it) }

    expect(screenshots.prepare.map { File.basename(it) }).to eq(%w[final.png])
  end

  it "keeps the smallest result, and never a larger one than it started with" do
    put("final.png")
    before = File.size(File.join(dir, "final.png"))

    screenshots.prepare

    aggregate_failures do
      expect(File.size(File.join(dir, "final.png"))).to eq(100).and be < before
      expect(Dir.children(dir)).to eq(%w[final.png])
    end
  end

  it "leaves a file alone when every tool would grow it" do
    put("final.png")
    before = File.binread(File.join(dir, "final.png"))

    described_class.new(dir:, tools: tools.slice("large"), which: ->(_) { true }, runner:).prepare

    expect(File.binread(File.join(dir, "final.png"))).to eq(before)
  end

  it "refuses an image that is not PNG, and deletes nothing" do
    put("final.png")
    FileUtils.cp(fixture, File.join(dir, "step-02.avif"))

    aggregate_failures do
      expect { screenshots.prepare(failing_step: 2) }.to raise_error(described_class::Refused, /not PNG.*step-02\.avif/)
      expect(Dir.children(dir).sort).to eq(%w[final.png step-02.avif])
    end
  end

  it "warns once and keeps the files as they are when neither tool is installed" do
    %w[step-01.png final.png].each { put(it) }
    allow(OpenLanes::UI).to receive(:log)

    screenshots(which: ->(_) { false }).prepare(failing_step: 1)

    aggregate_failures do
      expect(OpenLanes::UI).to have_received(:log).with(/neither small nor large is installed/, level: :warn).once
      expect(ran).to be_empty
    end
  end

  it "finds a tool on PATH and runs it, by default" do
    put("final.png")
    bin = Dir.mktmpdir("openlanes-bin")
    File.write(File.join(bin, "shrink"), "#!/bin/sh\nhead -c 64 \"$1\" > \"$2\"\n")
    File.chmod(0o755, File.join(bin, "shrink"))
    saved = ENV.fetch("PATH")
    ENV["PATH"] = "#{bin}#{File::PATH_SEPARATOR}#{saved}"

    described_class.new(dir:, tools: { "shrink" => ->(from, to) { ["shrink", from, to] }, "absent-tool" => ->(*) { ["absent-tool"] } }).prepare

    expect(File.size(File.join(dir, "final.png"))).to eq(64)
  ensure
    ENV["PATH"] = saved
    FileUtils.rm_rf(bin)
  end

  it "counts a tool that cannot be started as one that failed" do
    put("final.png")
    before = File.size(File.join(dir, "final.png"))

    described_class.new(dir:, tools: { "gone" => ->(from, to) { ["/nonexistent/gone", from, to] } }, which: ->(_) { true }).prepare

    expect(File.size(File.join(dir, "final.png"))).to eq(before)
  end

  it "tries vips first and magick after it, by default" do
    argv = described_class::TOOLS.map { |_, build| build.call("in.png", "out.png").first }

    expect(argv).to eq(%w[vips magick])
  end
end

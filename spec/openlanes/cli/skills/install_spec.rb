# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::Skills::Install do
  subject(:command) { described_class.new }

  let(:top) { File.realpath(Dir.mktmpdir("openlanes-skills-cli")) }
  let(:into) { File.join(top, "skills") }
  let(:bundled) { OpenLanes::Skills.bundled.map(&:name) }

  after { FileUtils.rm_rf(top) }

  def run(**)
    out = CapturedStream.new
    err = CapturedStream.new
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      command.call(into:, overwrite: false, dry_run: false, **)
    ensure
      $stdout, $stderr = original_out, original_err
    end
    [strip_ansi(out.string), strip_ansi(err.string)]
  end

  it "ships the seven openlanes skills" do
    expect(bundled).to eq(%w[openlanes openlanes-documents openlanes-run openlanes-setup openlanes-spec openlanes-status openlanes-sync])
  end

  it "installs each bundled skill and lists it on STDOUT" do
    out, = run
    expect(out.lines.map { it.split("\t").first(2) }).to eq(bundled.map { ["installed", it] })
  end

  it "keeps what is there on a second run, and says how to replace it" do
    run
    out, err = run
    expect([out.lines.map { it.split("\t").first }.uniq, unwrapped(err)])
      .to match([%w[kept], include("7 kept", "--overwrite")])
  end

  it "copies nothing under -n" do
    _out, err = run(dry_run: true)
    expect([Dir.exist?(into), unwrapped(err)]).to match([false, include("nothing was copied", "7 installed")])
  end

  # Runs anywhere: no project root is looked for.
  it "needs no project" do
    Dir.chdir(top)
    expect { run }.not_to raise_error
  end

  describe "-h" do
    def screen(*arguments)
      out = CapturedStream.new
      original = $stdout
      $stdout = out
      begin
        Dry::CLI.new(OpenLanes::CLI).call(arguments:)
      rescue SystemExit
        nil
      ensure
        $stdout = original
      end
      strip_ansi(out.string)
    end

    it "lists every bundled skill with its summary and whether it is installed" do
      expect(unwrapped(screen("skills", "install", "-h")))
        .to include(*%w[openlanes openlanes-documents openlanes-run openlanes-setup openlanes-spec openlanes-status openlanes-sync].map { "#{it} (" }, "installed) — The openlanes")
    end

    it "keeps the group screen to one line for the command" do
      expect(screen("skills", "-h")).not_to include("openlanes-run")
    end
  end
end

# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::Base do
  describe "#dry_run?" do
    subject { Class.new(described_class).new.send(:dry_run?, options) }

    let(:options) { {} }

    # A command does the work it is named for: no flag means do it.
    context "without --dry-run" do
      it { is_expected.to be(false) }
    end

    context "with --dry-run" do
      let(:options) { { dry_run: true } }

      it { is_expected.to be(true) }
    end
  end

  describe ".dry_run_option" do
    subject(:option) { OpenLanes::CLI::Run.options.find { |o| o.name == :dry_run } }

    it "declares -n, off by default" do
      expect([option.aliases, option.default]).to eq([["-n"], false])
    end
  end

  # `openlanes docs .plans/README.md` — the `-o` left out — used to run with every
  # default, write the file somewhere the caller never named, and report
  # success. dry-cli collects a token no command declared into :args and says
  # nothing about it.
  describe "a token no command declares" do
    subject(:run) do
      status = 0
      original = $stderr
      $stderr = err
      begin
        command.new.call(**options)
      rescue SystemExit => e
        status = e.status
      ensure
        $stderr = original
      end
      status
    end

    let(:err) { CapturedStream.new }
    let(:command) { Class.new(described_class) { def call(**) = nil } }
    let(:options) { { args: [".plans/README.md"] } }

    it { is_expected.to eq(64) }

    it "names the token it refused" do
      run

      expect(strip_ansi(err.string)).to include(".plans/README.md")
    end

    context "when the command declares an argument of its own" do
      let(:command) do
        Class.new(described_class) do
          argument :words, type: :array
          def call(**) = nil
        end
      end
      let(:options) { { words: %w[fix the thing], args: %w[fix the thing] } }

      it { is_expected.to eq(0) }
    end

    context "when nothing strays" do
      let(:options) { { args: [] } }

      it { is_expected.to eq(0) }
    end
  end

  # Typed three directories down, a command still works on the project's
  # own .plans, and says where that is.
  describe "entering the project" do
    subject(:run) do
      status = 0
      original = $stderr
      $stderr = err
      Dir.chdir(from)
      begin
        command.new.call(**options)
      rescue SystemExit => e
        status = e.status
      ensure
        $stderr = original
      end
      status
    end

    let(:top) { File.realpath(Dir.mktmpdir("openlanes-root")) }
    let(:err) { CapturedStream.new }
    let(:seen) { [] }
    let(:recorder) { seen }
    let(:command) do
      log = recorder
      Class.new(described_class) { define_method(:call) { |**| log << Dir.pwd } }
    end
    let(:options) { { args: [] } }
    let(:from) { File.join(top, "app", "lib") }

    after { FileUtils.rm_rf(top) }

    before { FileUtils.mkdir_p([from, File.join(top, "app", ".plans")]) }

    it "moves to the root before the command runs" do
      run

      expect(seen).to eq([File.join(top, "app")])
    end

    it "names the root on STDERR" do
      run

      expect(strip_ansi(err.string)).to include("Project root: #{File.join(top, "app")}")
    end

    context "with -q" do
      let(:options) { { args: [], quiet: true } }

      it "moves without a word" do
        run

        expect([seen, err.string]).to eq([[File.join(top, "app")], ""])
      end
    end

    context "when already at the root" do
      let(:from) { File.join(top, "app") }

      it "says nothing" do
        run

        expect(err.string).to eq("")
      end
    end

    context "when nothing above is a project" do
      let(:from) { File.join(top, "loose") }

      before { FileUtils.mkdir_p(from) }

      it { is_expected.to eq(66) }

      it "points at openlanes init" do
        run

        expect(unwrapped(strip_ansi(err.string))).to include("No project here", "openlanes init")
      end
    end

    context "with a command that needs no project" do
      let(:command) do
        log = recorder
        Class.new(described_class) do
          standalone!
          define_method(:call) { |**| log << Dir.pwd }
        end
      end

      it "stays where it was typed" do
        run

        expect(seen).to eq([from])
      end
    end
  end

  # Every workflow fails the same way, so every command refuses the same way.
  describe "#unwrap" do
    subject(:command) { Class.new(described_class).new }

    let(:err) { CapturedStream.new }

    def unwrapped(result)
      original = $stderr
      $stderr = err
      [command.send(:unwrap, result), 0]
    rescue SystemExit => e
      [nil, e.status]
    ensure
      $stderr = original
    end

    it "answers the success value and prints nothing" do
      expect(unwrapped(Dry::Monads::Result::Success.new(7))).to eq([7, 0])
      expect(err.string).to be_empty
    end

    it "exits with the refusal's status and prints its message" do
      refusal = OpenLanes::Refusal.new(message: "No plan 999", status: 66)

      expect(unwrapped(Dry::Monads::Result::Failure.new(refusal))).to eq([nil, 66])
      expect(strip_ansi(err.string)).to include("No plan 999")
    end
  end
end

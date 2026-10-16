# frozen_string_literal: true

require "json"

RSpec.describe OpenLanes::Log do
  let(:root) { Dir.mktmpdir("openlanes-log") }

  after { FileUtils.rm_rf(root) }

  def settings(**options) = OpenLanes::Log::Settings.from(options, root: root, env: {})

  describe OpenLanes::Log::Settings do
    it "defaults to log/development.log under the root, at info, one line per entry" do
      expect(settings).to have_attributes(file: File.join(root, "log", "development.log"), level: "info", format: "standard")
    end

    it "takes a relative --log from the root, not the working directory" do
      expect(settings(log: "tmp/run.log").file).to eq(File.join(root, "tmp", "run.log"))
    end

    it "keeps - for STDOUT" do
      expect(settings(log: "-")).to have_attributes(file: "-", stdout?: true)
    end

    it "takes what the engine handed down through the environment when no flag is typed" do
      env = { "OPENLANES_LOG" => "/var/run.log", "OPENLANES_LOG_LEVEL" => "debug", "OPENLANES_LOG_FORMAT" => "json" }

      aggregate_failures do
        expect(described_class.from({}, root: root, env:)).to have_attributes(file: "/var/run.log", level: "debug", format: "json")
        expect(described_class.from({ log_level: "warn" }, root: root, env:).level).to eq("warn")
      end
    end

    it "round-trips through the environment it hands a child" do
      original = settings(log: "x.log", log_level: "WARN", log_format: "json")

      expect(described_class.from({}, root: "/elsewhere", env: original.env)).to eq(original)
    end

    it "refuses a level or a format it does not know" do
      aggregate_failures do
        expect { settings(log_level: "loud") }.to raise_error(OpenLanes::Log::Invalid, /--log-level loud/)
        expect { settings(log_format: "xml") }.to raise_error(OpenLanes::Log::Invalid, /--log-format xml: use one of standard, json/)
      end
    end
  end

  describe ".setup" do
    let(:file) { File.join(root, "log", "development.log") }

    it "creates the log directory and writes there, signed with the process's name" do
      described_class.setup(settings, name: "engine")
      described_class.logger.info("hello")

      aggregate_failures do
        expect(described_class).to be_configured
        expect(described_class.path).to eq(file)
        expect(File.read(file)).to match(/ I \[#{Process.pid}:[^\]]+\] engine -- hello\n\z/)
      end
    end

    it "appends to what another process already wrote" do
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, "from the other process\n")
      described_class.setup(settings)
      described_class.logger.info("ours")

      expect(File.readlines(file)).to match([
                                              "from the other process\n",
                                              a_string_including("openlanes -- ours")
                                            ])
    end

    it "writes nothing below its level" do
      described_class.setup(settings(log_level: "warn"))
      described_class.logger.info("quiet")
      described_class.logger.warn("loud")

      expect(File.read(file)).to include("loud").and(satisfy { !it.include?("quiet") })
    end

    it "writes one JSON object per line under --log-format json" do
      described_class.setup(settings(log_format: "json"), name: "web")
      described_class.event("started", plan: "003.00", seconds: 4.26, agent: nil)
      entry = JSON.parse(File.read(file))

      expect(entry).to include("name" => "web",
        "level" => "info",
        "message" => "started",
        "payload" => { "plan" => "003.00", "seconds" => 4.3 })
    end

    it "keeps a stack trace on one line in the standard format" do
      described_class.setup(settings)
      described_class.logger.error("boom", RuntimeError.new("first\nsecond"))

      expect(File.readlines(file).size).to eq(1)
    end

    it "replaces its appender when set up again, rather than writing every line twice" do
      described_class.setup(settings)
      other = File.join(root, "other.log")
      described_class.setup(settings(log: other))
      described_class.logger.info("once")

      aggregate_failures do
        expect(File.read(other).scan("once").size).to eq(1)
        expect(File.read(file)).not_to include("once")
      end
    end

    it "writes to STDOUT for --log -" do
      expect {
        described_class.setup(settings(log: "-"))
        described_class.logger.info("to stdout")
      }.to output(/openlanes -- to stdout/).to_stdout

      expect(described_class.path).to be_nil
    end
  end

  describe ".event" do
    it "is a no-op before setup" do
      aggregate_failures do
        expect { described_class.event("nothing") }.not_to raise_error
        expect(described_class).not_to be_configured
        expect(Dir.exist?(File.join(root, "log"))).to be(false)
      end
    end
  end
end

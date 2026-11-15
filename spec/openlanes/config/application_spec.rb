# frozen_string_literal: true

RSpec.describe OpenLanes::Config::Application do
  let(:path) { ".openlanes/config.yml" }

  def parse(yaml) = OpenLanes::Config.parse(yaml, path:).application

  it "reads the name, description, phase and commands" do
    application = parse(<<~YAML)
      application:
        name: Demo App
        description: Books appointments
        current_phase: in-production
        commands:
          setup: bin/setup
          start: [bin/rails server, bin/vite dev]
          stop: pkill -f rails
          ci_tests: just ci
    YAML

    expect(application).to have_attributes(name: "Demo App", description: "Books appointments", current_phase: :'in-production')
    expect(application.commands).to eq(setup: "bin/setup", start: ["bin/rails server", "bin/vite dev"], stop: ["pkill -f rails"], ci_tests: "just ci")
    expect(application.command(:start)).to eq(["bin/rails server", "bin/vite dev"])
    expect(application.command("after_stop")).to be_nil
  end

  it "is nil when the file has no section" do
    expect(parse("project: Demo App\n")).to be_nil
  end

  it "reads a section of empty keys, as init writes it, as nothing said" do
    expect(parse(<<~YAML)).to be_nil
      application:
        name:
        description: "  "
        current_phase:
        commands:
          setup:
          start: []
          stop: []
    YAML
  end

  it "accepts every phase the schema names" do
    expect(described_class::PHASES).to eq(%i[mvp alpha beta in-production])
    described_class::PHASES.each do |phase|
      expect(parse("application: { current_phase: #{phase} }\n").current_phase).to eq(phase)
    end
  end

  it "writes back only what was given" do
    yaml = "application:\n  name: Demo App\n  commands:\n    start:\n    - bin/dev\n"
    config = OpenLanes::Config.parse(yaml, path:)

    expect(config.to_settings["application"]).to eq("name" => "Demo App", "commands" => { "start" => ["bin/dev"] })
    expect(OpenLanes::Config.parse(config.to_yaml, path:).application).to eq(config.application)
  end

  it "writes every key, empty, into the file init produces" do
    written = YAML.safe_load(OpenLanes::Config.new.to_yaml)["application"]

    expect(written.keys).to eq(described_class::KEYS)
    expect(written["commands"].keys).to eq(described_class::COMMANDS)
    expect(written["commands"]).to include("start" => [], "stop" => [], "setup" => nil)
  end

  {
    "application: 3\n"                                     => /application: must be a mapping/,
    "application: { nmae: Demo }\n"                        => /application: unknown key nmae; known: name, description/,
    "application: { name: 3 }\n"                           => /application\.name: must be text, not 3/,
    "application: { current_phase: gamma }\n"              => /application\.current_phase: "gamma" is not one of mvp, alpha, beta, in-production/,
    "application: { commands: [bin/dev] }\n"               => /application\.commands: must be a mapping/,
    "application: { commands: { strat: bin/dev } }\n"      => /application\.commands: unknown key strat; known: setup/,
    "application: { commands: { start: [bin/dev, 3] } }\n" => /application\.commands\.start: must be text, not 3/,
    "application: { commands: { setup: [bin/setup] } }\n"  => /application\.commands\.setup: must be text/
  }.each do |yaml, message|
    it "refuses #{yaml.strip}" do
      expect { parse(yaml) }.to raise_error(OpenLanes::Error, message)
    end
  end
end

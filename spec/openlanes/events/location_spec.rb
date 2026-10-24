# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Events::Location do
  let(:root) { Dir.mktmpdir("demo") }
  let(:config) { OpenLanes::Config.new }

  after { FileUtils.rm_rf(root) }

  it "puts the log under XDG_STATE_HOME when it is set" do
    dir = described_class.dir(root:, config:, env: { "XDG_STATE_HOME" => "/state" })

    expect(dir).to match(%r{\A/state/openlanes/#{File.basename(root)}-\h{6}/events\z})
  end

  it "falls back to ~/.local/state when it is unset" do
    expect(described_class.dir(root:, config:, env: {}))
      .to start_with(File.expand_path("~/.local/state/openlanes/"))
  end

  it "ignores a relative XDG_STATE_HOME, as the XDG spec says" do
    expect(described_class.dir(root:, config:, env: { "XDG_STATE_HOME" => "state" }))
      .to start_with(File.expand_path("~/.local/state/openlanes/"))
  end

  it "takes events.dir over the default" do
    expect(described_class.dir(root:, config: OpenLanes::Config.new(events_dir: "/var/log/ol"), env: {}))
      .to eq("/var/log/ol")
  end

  it "keeps two checkouts of one name apart" do
    other = Dir.mktmpdir("demo")
    expect(described_class.digest(root)).not_to eq(described_class.digest(other))
  ensure
    FileUtils.rm_rf(other)
  end
end

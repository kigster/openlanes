# frozen_string_literal: true

RSpec.describe OpenLanes::Slack::Settings do
  let(:config) { OpenLanes::Config.new(slack: { channel: "#file", workspace: "T0FILE", operators: ["UFILE"], poll_seconds: 5 }) }

  def settings(env = {}) = described_class.from(config:, env:)

  it "is what .openlanes/config.yml says when the environment says nothing" do
    expect(settings).to have_attributes(channel: "#file", workspace: "T0FILE", operators: ["UFILE"], interval: 5)
  end

  it "takes each setting from the environment over the file" do
    env = { "OPENLANES_SLACK_CHANNEL" => "C0ENV", "OPENLANES_SLACK_WORKSPACE" => "T0ENV", "OPENLANES_SLACK_OPERATORS" => "UONE, UTWO" }

    expect(settings(env)).to have_attributes(channel: "C0ENV", workspace: "T0ENV", operators: %w[UONE UTWO], interval: 5)
  end

  it "needs no slack: section at all when the environment has the channel and the operators" do
    env = { "OPENLANES_SLACK_CHANNEL" => "C0ENV", "OPENLANES_SLACK_OPERATORS" => "UONE UTWO" }

    expect(described_class.from(config: OpenLanes::Config.new, env:))
      .to have_attributes(channel: "C0ENV", workspace: nil, operators: %w[UONE UTWO], interval: OpenLanes::Slack::DEFAULT_INTERVAL)
  end

  it "reads a blank variable as unset, so an empty line in .env does not erase the file" do
    env = { "OPENLANES_SLACK_CHANNEL" => " ", "OPENLANES_SLACK_OPERATORS" => " , " }

    expect(settings(env)).to have_attributes(channel: "#file", operators: ["UFILE"])
  end

  it "refuses an operator that is not a Slack user id, as the file's schema does" do
    expect { settings("OPENLANES_SLACK_OPERATORS" => "UONE,@kim") }
      .to raise_error(OpenLanes::Error, /OPENLANES_SLACK_OPERATORS: "@kim" is not a Slack user id/)
  end
end

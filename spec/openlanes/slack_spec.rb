# frozen_string_literal: true

RSpec.describe OpenLanes::Slack do
  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/example/openlanes", node: "aaaa:bbbb") }
  let(:env) { { "SLACK_BOT_TOKEN" => "xoxb-test" } }
  let(:configured) { OpenLanes::Config.new(slack: { channel: "#questions", workspace: "acme", operators: ["UKIM"], poll_seconds: 5 }) }

  before { allow(OpenLanes::UI).to receive(:log) }

  describe ".bridge" do
    it "is nil for a project with neither a channel nor a token, and says nothing" do
      expect(described_class.bridge(store:, keys:, config: OpenLanes::Config.new, env: {})).to be_nil
      expect(OpenLanes::UI).not_to have_received(:log)
    end

    it "is nil with a token and no channel, and says where a channel goes" do
      expect(described_class.bridge(store:, keys:, config: OpenLanes::Config.new, env:)).to be_nil
      expect(OpenLanes::UI).to have_received(:log)
        .with(%r{SLACK_BOT_TOKEN is set but no channel is: set slack\.channel in \.openlanes/config\.yml or OPENLANES_SLACK_CHANNEL}, level: :warn)
    end

    it "is nil when the operators cannot be read, rather than stopping the run" do
      env = { "SLACK_BOT_TOKEN" => "xoxb-test", "OPENLANES_SLACK_CHANNEL" => "C0ENV", "OPENLANES_SLACK_OPERATORS" => "@kim" }

      expect(described_class.bridge(store:, keys:, config: OpenLanes::Config.new, env:)).to be_nil
      expect(OpenLanes::UI).to have_received(:log).with(/"@kim" is not a Slack user id/, level: :warn)
    end

    it "is a bridge on the environment alone" do
      env = { "SLACK_BOT_TOKEN" => "xoxb-test", "OPENLANES_SLACK_CHANNEL" => "C0ENV", "OPENLANES_SLACK_OPERATORS" => "UKIM" }

      expect(described_class.bridge(store:, keys:, config: OpenLanes::Config.new, env:)).to be_a(described_class::Bridge)
    end

    it "is nil without a token, and says which variable is missing" do
      expect(described_class.bridge(store:, keys:, config: configured, env: {})).to be_nil
      expect(OpenLanes::UI).to have_received(:log).with(/a channel is configured but SLACK_BOT_TOKEN is not set/, level: :warn)
    end

    it "is nil without operators, and says that anyone in the channel will not do (HM4)" do
      config = OpenLanes::Config.new(slack: { channel: "#questions" })

      expect(described_class.bridge(store:, keys:, config:, env:)).to be_nil
      expect(OpenLanes::UI).to have_received(:log).with(/no slack\.operators .*steers an agent.*, so questions are asked in the control room only/, level: :warn)
    end

    it "takes an empty or blank list as nobody named" do
      config = OpenLanes::Config.new(slack: { channel: "#questions", operators: [""] })

      expect(described_class.bridge(store:, keys:, config:, env:)).to be_nil
    end

    it "is a bridge once the channel, the token and the operators are all there" do
      expect(described_class.bridge(store:, keys:, config: configured, env:)).to be_a(described_class::Bridge)
    end
  end

  describe ".room" do
    it "is the channel the environment names, over the configured one" do
      expect(described_class.room(config: configured, env: env.merge("OPENLANES_SLACK_CHANNEL" => "C0ENV")).channel).to eq("C0ENV")
    end

    it "is the configured channel" do
      expect(described_class.room(config: configured, env:).channel).to eq("#questions")
    end

    it "says how to configure a channel when there is none" do
      expect { described_class.room(config: OpenLanes::Config.new, env:) }
        .to raise_error(OpenLanes::Error, %r{no Slack channel\. Add to \.openlanes/config\.yml:.*slack:\n    channel:}m)
    end

    it "names who may answer" do
      expect { described_class.room(config: OpenLanes::Config.new(slack: { channel: "#questions" }), env:) }
        .to raise_error(OpenLanes::Error, /no slack\.operators .*Copy member ID/)
    end

    it "needs the token" do
      expect { described_class.room(config: configured, env: {}) }.to raise_error(OpenLanes::Error, /Set SLACK_BOT_TOKEN/)
    end
  end
end

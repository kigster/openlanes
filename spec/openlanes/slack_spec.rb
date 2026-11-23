# frozen_string_literal: true

RSpec.describe OpenLanes::Slack do
  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/example/openlanes", node: "aaaa:bbbb") }
  let(:env) { { "SLACK_BOT_TOKEN" => "xoxb-test" } }
  let(:configured) { OpenLanes::Config.new(slack: { channel: "#questions", workspace: "acme", operators: ["UKIM"], poll_seconds: 5 }) }

  before { allow(OpenLanes::UI).to receive(:log) }

  describe ".bridge" do
    it "is nil for a project with no slack: section, and says nothing" do
      expect(described_class.bridge(store:, keys:, config: OpenLanes::Config.new, env:)).to be_nil
      expect(OpenLanes::UI).not_to have_received(:log)
    end

    it "is nil without a token, and says which variable is missing" do
      expect(described_class.bridge(store:, keys:, config: configured, env: {})).to be_nil
      expect(OpenLanes::UI).to have_received(:log).with(/names a channel but SLACK_BOT_TOKEN is not set/, level: :warn)
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

# frozen_string_literal: true

require_relative "../../support/fake_slack"

# A seam, like {OpenLanes::Linear::API}. What is worth pinning is how Slack
# says no, since it does so with HTTP 200, and what goes over the wire.
RSpec.describe OpenLanes::Slack::API do
  let(:slack) { FakeSlack.new }
  let(:api) { slack.api }

  it "refuses to be built with no way to authenticate" do
    expect { described_class.new }.to raise_error(OpenLanes::Error, /Set SLACK_BOT_TOKEN/)
  end

  it "reads the token from the environment, and a blank one as none" do
    expect(described_class.token_from("SLACK_BOT_TOKEN" => " xoxb-1 ")).to eq("xoxb-1")
    expect(described_class.token_from("SLACK_BOT_TOKEN" => " ")).to be_nil
  end

  it "posts blocks as JSON text, which is what a form-encoded call carries" do
    sent = api.post(channel: "#q", text: "hello", blocks: [{ type: "section" }])

    expect(sent).to include("channel" => "C0QUESTIONS")
    expect(slack.called("chat.postMessage").first).to include("channel" => "#q", "blocks" => '[{"type":"section"}]')
  end

  it "raises Slack's own word for a refusal, and the scope it wants" do
    transport = ->(_method, _params) { { "ok" => false, "error" => "missing_scope", "needed" => "reactions:write" } }

    expect { described_class.new(transport:).identity }
      .to raise_error(described_class::Refused, /auth\.test: missing_scope \(the app needs the reactions:write scope\)/)
  end

  it "takes a reaction that is already there as done" do
    posted = api.post(channel: "#q", text: "t", blocks: []).fetch("ts")

    2.times { api.react(channel: "C0QUESTIONS", at: posted, name: "one") }

    expect(api.reactions(channel: "C0QUESTIONS", at: posted)).to eq([{ "name" => "one", "users" => ["UBOT"], "count" => 1 }])
  end

  it "does not swallow any other refusal to react" do
    slack.refuse("reactions.add", "invalid_name")

    expect { api.react(channel: "C1", at: "1.0", name: "nope") }.to raise_error(described_class::Refused, /invalid_name/)
  end

  it "replies in a thread and reads the thread back, the message first" do
    posted = api.post(channel: "#q", text: "t", blocks: []).fetch("ts")
    api.reply(channel: "C0QUESTIONS", at: posted, text: "noted")

    expect(api.thread(channel: "C0QUESTIONS", at: posted).map { it["text"] }).to eq(%w[t noted])
  end

  it "looks a user up" do
    expect(api.user("UDANA")).to include("real_name" => "Dana Okafor")
  end

  describe "over HTTP" do
    subject(:api) { described_class.new(token: "xoxb-test") }

    let(:http) { instance_double(Net::HTTP) }

    def answer_with(klass, code, body: "{}", headers: {})
      response = klass.new("1.1", code, "")
      headers.each { |key, value| response[key] = value }
      allow(response).to receive(:body).and_return(body)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(response)
    end

    it "sends the token as a bearer and the parameters as a form" do
      answer_with(Net::HTTPOK, "200", body: '{"ok":true,"team":"Acme"}')

      expect(api.identity).to include("team" => "Acme")
      expect(http).to have_received(:request) do |request|
        expect(request["Authorization"]).to eq("Bearer xoxb-test")
        expect(request.path).to eq("/api/auth.test")
      end
    end

    it "says how long Slack wants to be left alone" do
      answer_with(Net::HTTPTooManyRequests, "429", headers: { "Retry-After" => "7" })

      expect { api.identity }.to raise_error(described_class::RateLimited) { expect(it.retry_after).to eq(7) }
    end

    it "reports any other HTTP failure by its code" do
      answer_with(Net::HTTPBadGateway, "502")

      expect { api.identity }.to raise_error(OpenLanes::Error, /HTTP 502/)
    end

    it "reports a network failure as its own error, never a raw one" do
      allow(Net::HTTP).to receive(:start).and_raise(SocketError, "getaddrinfo: nodename nor servname provided")

      expect { api.identity }.to raise_error(OpenLanes::Error, /Slack did not answer auth\.test: getaddrinfo/)
    end
  end
end

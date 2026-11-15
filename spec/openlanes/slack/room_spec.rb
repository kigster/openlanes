# frozen_string_literal: true

require_relative "../../support/fake_slack"

RSpec.describe OpenLanes::Slack::Room do
  subject(:room) { described_class.new(api: slack.api, channel: "#questions", workspace:, operators:) }

  let(:slack) { FakeSlack.new }
  let(:workspace) { nil }
  let(:operators) { [] }
  let(:question) do
    { "id" => "003.00/B1", "kind" => "block", "heading" => "B1 — Ship it?",
      "options" => [{ "label" => "yes", "answer" => "yes" }, { "label" => "no", "answer" => "no" }] }
  end
  let(:poll) { OpenLanes::Slack::Poll.new(plan: { "ordinal" => "003.00", "title" => "Tax Rule DSL" }, question:) }

  describe "the workspace" do
    %w[T0ACME acme Acme].each do |name|
      context "when slack.workspace is #{name}" do
        let(:workspace) { name }

        it "is the token's, by id, name or subdomain" do
          expect(room.identity).to include("team_id" => "T0ACME")
        end
      end
    end

    context "when the token belongs to another one" do
      let(:workspace) { "globex" }

      it "posts nothing there" do
        expect { room.post(poll) }.to raise_error(OpenLanes::Error, /slack\.workspace is globex, but SLACK_BOT_TOKEN belongs to Acme/)
        expect(slack.posts).to be_empty
      end
    end
  end

  it "posts the question, then puts its ballot on in order" do
    ref = room.post(poll)
    room.decorate(ref, poll)

    expect(ref).to have_attributes(channel: "C0QUESTIONS")
    expect(slack.called("reactions.add").map { it["name"] }).to eq(%w[one two])
    expect(slack.called("reactions.add").map { it["channel"] }.uniq).to eq(["C0QUESTIONS"])
  end

  it "asks Slack who it is once, however many polls go out" do
    2.times { room.post(poll) }

    expect(slack.called("auth.test").size).to eq(1)
  end

  it "says what to do about a channel the app is not in" do
    slack.refuse("chat.postMessage", "not_in_channel")

    expect { room.post(poll) }.to raise_error(OpenLanes::Error, %r{not_in_channel; invite the app to the channel: /invite})
  end

  it "leaves a refusal it has no advice for as Slack worded it" do
    slack.refuse("chat.postMessage", "msg_too_long")

    expect { room.post(poll) }.to raise_error(OpenLanes::Slack::API::Refused, /msg_too_long/)
  end

  describe "#vote" do
    let(:ref) { room.post(poll).tap { room.decorate(it, poll) } }

    it "is nil until a person answers, then their choice" do
      expect(room.vote(ref, poll)).to be_nil

      slack.click(ref.ts, "two")

      expect(room.vote(ref, poll)).to have_attributes(user: "UDANA", text: "no")
    end

    it "reads the reactions apart when the thread comes back without them" do
      slack.bare!
      slack.click(ref.ts, "one")

      expect(room.vote(ref, poll).text).to eq("yes")
      expect(slack.called("reactions.get").size).to eq(1)
    end

    context "with operators named" do
      let(:operators) { ["UKIM"] }

      it "hears only them" do
        slack.click(ref.ts, "one", user: "UDANA")
        expect(room.vote(ref, poll)).to be_nil

        slack.say(ref.ts, "no, hold it", user: "UKIM")
        expect(room.vote(ref, poll)).to have_attributes(user: "UKIM", text: "no, hold it")
      end
    end
  end

  it "closes a poll by saying what became of it" do
    ref = room.post(poll)
    room.close(ref, poll, "Answered in the control room.")

    expect(slack.text_of(ref.ts)).to end_with("Answered in the control room.")
  end

  describe "#name_of" do
    it "is the person's name, asked for once" do
      expect([room.name_of("UDANA"), room.name_of("UDANA")]).to eq(["Dana Okafor", "Dana Okafor"])
      expect(slack.called("users.info").size).to eq(1)
    end

    it "is their id when the app may not read users" do
      slack.refuse("users.info", "missing_scope")

      expect(room.name_of("UDANA")).to eq("UDANA")
    end
  end
end

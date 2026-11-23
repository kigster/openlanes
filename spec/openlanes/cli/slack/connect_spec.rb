# frozen_string_literal: true

require "tmpdir"
require_relative "../../../support/fake_slack"

RSpec.describe OpenLanes::CLI::Slack::Connect do
  subject(:command) { described_class.new(env:, prompt:) }

  let(:env) { { "SLACK_BOT_TOKEN" => "xoxb-env" } }
  let(:prompt) { instance_double(TTY::Prompt, mask: nil) }
  let(:slack) { FakeSlack.new }
  let(:dir) { File.realpath(Dir.mktmpdir) }
  let(:dotenv) { File.join(dir, ".env") }
  let(:app_env) { File.join(dir, "app.env") }

  def run(operators: "UDANA", channel: "#questions", test: false, **)
    out, err, status = CapturedStream.capture { command.call(operators:, channel:, test:, timeout: 0, **) }
    [strip_ansi(out), strip_ansi(err), status.to_i]
  end

  before do
    allow(OpenLanes::Slack).to receive(:api).and_return(slack.api)
    allow(OpenLanes::Project).to receive(:root).and_return(dir)
    system("git", "init", "-q", dir)
    File.write(File.join(dir, ".gitignore"), ".env\n")
  end

  around { |example| Dir.chdir(dir) { example.run } }

  after { FileUtils.remove_entry(dir) }

  it "writes the channel, the token's workspace and the operators to the project's .env" do
    out, err, status = run

    expect([out, status]).to eq(["", 0])
    expect(File.read(dotenv)).to eq("SLACK_BOT_TOKEN=xoxb-env\nOPENLANES_SLACK_CHANNEL='#questions'\n" \
                                    "OPENLANES_SLACK_OPERATORS=UDANA\nOPENLANES_SLACK_WORKSPACE=T0ACME\n")
    expect(err).to include("Acme (T0ACME)", "openlanes start")
  end

  it "never prints the token" do
    out, err, = run

    expect(out + err).not_to include("xoxb-env")
  end

  it "takes a public channel's name without its #, which a shell reads as a comment" do
    run(channel: "questions")

    expect(File.read(dotenv)).to include("OPENLANES_SLACK_CHANNEL='#questions'")
  end

  it "takes a channel's id as it is" do
    run(channel: "C0123ABCD")

    expect(File.read(dotenv)).to include("OPENLANES_SLACK_CHANNEL=C0123ABCD\n")
  end

  it "takes the token from the Slack app's .env and writes the settings there too" do
    File.write(app_env, "SLACK_BOT_TOKEN=xoxb-app\nSLACK_APP_TOKEN=xapp\n")
    run(app_env:)

    expect(OpenLanes::Slack).to have_received(:api).with(env: hash_including("SLACK_BOT_TOKEN" => "xoxb-app")).at_least(:once)
    expect(File.read(dotenv)).to include("SLACK_BOT_TOKEN=xoxb-app")
    expect(File.read(dotenv)).not_to include("xapp")
    expect(File.read(app_env)).to include("SLACK_APP_TOKEN=xapp\nOPENLANES_SLACK_CHANNEL='#questions'\n")
  end

  it "changes nothing on a dry run, and says what it would" do
    _, err, status = run(dry_run: true)

    expect(status).to eq(0)
    expect(File.exist?(dotenv)).to be(false)
    expect(err).to include("OPENLANES_SLACK_CHANNEL", dotenv, "Dry run")
    expect(slack.called("chat.postMessage")).to be_empty
  end

  it "asks in the channel already configured when none is named" do
    File.write(dotenv, "OPENLANES_SLACK_CHANNEL=C0OLDONE\n")
    run(channel: nil)

    expect(File.read(dotenv)).to include("OPENLANES_SLACK_CHANNEL=C0OLDONE\n")
  end

  it "asks in the channel .openlanes/config.yml names when none is named or set, since .env would win over it" do
    FileUtils.mkdir_p(File.join(dir, ".openlanes"))
    File.write(File.join(dir, ".openlanes", "config.yml"), "slack:\n  channel: \"#from-config\"\n")
    run(channel: nil)

    expect(File.read(dotenv)).to include("OPENLANES_SLACK_CHANNEL='#from-config'")
  end

  it "asks in #openlanes-questions when none is named or configured" do
    run(channel: nil)

    expect(File.read(dotenv)).to include("OPENLANES_SLACK_CHANNEL='#openlanes-questions'")
  end

  it "refuses an operator that is not a Slack user id, and writes nothing" do
    _, err, status = run(operators: "@dana")

    expect(status).to eq(69)
    expect(err).to include("@dana", "not a Slack user id")
    expect(File.exist?(dotenv)).to be(false)
  end

  context "without a token" do
    before { env.clear }

    it "links to Slack's new-app page with the manifest filled in, and refuses when nobody types one" do
      _, err, status = run

      expect(status).to eq(64)
      expect(err).to include("https://api.slack.com/apps?new_app=1&manifest_yaml=", "chat%3Awrite", "Set SLACK_BOT_TOKEN")
    end

    it "takes the token a person types" do
      allow(prompt).to receive(:mask).and_return(" xoxb-typed ")
      run

      expect(File.read(dotenv)).to include("SLACK_BOT_TOKEN=xoxb-typed\n")
    end
  end

  it "refuses a .env git would commit, since the token goes in it" do
    File.write(File.join(dir, ".gitignore"), "")
    _, err, status = run

    expect(status).to eq(77)
    expect(err).to include("not ignored")
    expect(File.exist?(dotenv)).to be(false)
  end

  it "refuses a workspace the token does not belong to, and writes nothing" do
    _, err, status = run(workspace: "T0OTHER")

    expect(status).to eq(69)
    expect(err).to include("T0OTHER")
    expect(File.exist?(dotenv)).to be(false)
  end

  it "posts the test poll to the channel it just configured" do
    _, err, status = run(test: true)

    expect(status).to eq(75)
    expect(err).to include("nobody answered it in time")
    expect(slack.called("chat.postMessage").first).to include("channel" => "#questions")
  end
end

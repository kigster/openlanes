# frozen_string_literal: true

# Each adapter's probe (plan 040, D5), against a scripted runner: no example
# here starts a CLI.
RSpec.describe "Adapter probes" do
  subject(:availability) { OpenLanes::Adapters.for(name).probe(runner:, at:) }

  let(:at) { Time.utc(2026, 10, 27, 9) }
  let(:result) { ->(stdout = "", status: 0, stderr: "") { OpenLanes::Adapters::ProbeRunner::Result.new(stdout:, stderr:, status:) } }
  let(:runner) { ScriptedProbeRunner.new(installed: [name], answers:) }
  let(:answers) { {} }

  shared_examples "a probe that says it timed out" do |argv|
    let(:answers) { { argv => result.call("", status: nil, stderr: "timed out after 15s") } }

    it { is_expected.not_to be_available }
    it { expect(availability.reason).to eq("`#{name}` did not answer: timed out after 15s") }
  end

  OpenLanes::Adapters.names.each do |adapter|
    context "with #{adapter} not installed" do
      let(:name) { adapter }
      let(:runner) { ScriptedProbeRunner.new(installed: []) }

      it { expect(availability.reason).to eq("not installed (no `#{adapter}` on PATH)") }

      it "asks the CLI nothing" do
        availability
        expect(runner.calls).to be_empty
      end
    end
  end

  context "with claude" do
    let(:name) { "claude" }
    let(:argv) { %w[claude auth status --json] }

    context "when signed in" do
      let(:answers) { { argv => result.call(%({"loggedIn": true, "email": "someone@example.com"})) } }

      it { is_expected.to be_available }
      it { expect(availability.models).to eq(OpenLanes::Adapters::Claude::MODELS) }
      it { expect(availability.checked_at).to eq(at) }
    end

    context "when signed out" do
      let(:answers) { { argv => result.call(%({"loggedIn": false}), status: 1) } }

      it { expect(availability.reason).to eq("not signed in (run `claude auth login`)") }
    end

    context "when the answer is not JSON" do
      let(:answers) { { argv => result.call("Error: unknown command") } }

      it { is_expected.not_to be_available }
    end

    it_behaves_like "a probe that says it timed out", %w[claude auth status --json]
  end

  context "with codex" do
    let(:name) { "codex" }
    let(:login) { %w[codex login status] }
    let(:models) { %w[codex debug models --bundled] }
    let(:listed) do
      JSON.generate(models: [{ slug: "gpt-6-sol", display_name: "GPT-6-Sol", visibility: "list", context_window: 272_000 },
                             { slug: "gpt-daybreak", display_name: "Daybreak", visibility: "hide" },
                             { slug: "gpt-5.5", visibility: "list" }])
    end

    context "when signed in" do
      let(:answers) { { login => result.call("Logged in using ChatGPT"), models => result.call(listed) } }

      it { is_expected.to be_available }
      it { expect(availability.models.map { [it.id, it.label, it.context] }).to eq([["gpt-6-sol", "GPT-6-Sol", 272_000], ["gpt-5.5", "gpt-5.5", 200_000]]) }
      it { expect(availability.models).to all(satisfy { !it.priced? }) }
    end

    # Grok on #151: an available adapter with no models offered the page
    # an empty dropdown. pi already says down when it lists none.
    context "when signed in but the model list cannot be read" do
      let(:answers) { { login => result.call(""), models => result.call("not json") } }

      it { expect([availability.available?, availability.reason]).to eq([false, "signed in, but `codex debug models --bundled` listed no models"]) }
    end

    context "when signed in but the model list command fails" do
      let(:answers) { { login => result.call("") } }

      it { expect([availability.available?, availability.reason]).to eq([false, "signed in, but `codex debug models --bundled` listed no models"]) }
    end

    context "when signed out" do
      let(:answers) { { login => result.call("Not logged in", status: 1) } }

      it { expect(availability.reason).to eq("not signed in (run `codex login`)") }

      it "does not ask for the models" do
        availability
        expect(runner.calls).to eq([login])
      end
    end

    it_behaves_like "a probe that says it timed out", %w[codex login status]
  end

  context "with pi" do
    let(:name) { "pi" }
    let(:argv) { %w[pi --list-models] }

    context "with a provider signed in" do
      let(:table) do
        <<~TABLE
          provider   model           context  max-out  thinking  images
          anthropic  claude-opus-5   200K     32K      yes       yes
          openai     gpt-5.5         272K     128K     yes       yes
        TABLE
      end
      let(:answers) { { argv => result.call(table) } }

      it { is_expected.to be_available }
      it { expect(availability.models.map(&:id)).to eq(%w[anthropic/claude-opus-5 openai/gpt-5.5]) }
    end

    context "with none" do
      let(:answers) { { argv => result.call("No models available. Use /login to log into a provider.\n") } }

      it { expect(availability.reason).to eq("no model provider signed in (run `pi`, then `/login`)") }
    end

    it_behaves_like "a probe that says it timed out", %w[pi --list-models]
  end

  context "with grok" do
    let(:name) { "grok" }
    let(:argv) { %w[grok models] }

    context "when signed in" do
      let(:listing) do
        <<~LISTING
          You are logged in with grok.com.

          Default model: grok-4.7

          Available models:
            * grok-4.7 (default)
            - grok-4.7-build-fast
        LISTING
      end
      let(:answers) { { argv => result.call(listing) } }

      it { is_expected.to be_available }
      it { expect(availability.models.map(&:id)).to eq(%w[grok-4.7 grok-4.7-build-fast]) }
    end

    context "when signed out, which still exits 0" do
      let(:answers) { { argv => result.call("You are not logged in.\n") } }

      it { expect(availability.reason).to eq("not signed in (run `grok login`)") }
    end

    it_behaves_like "a probe that says it timed out", %w[grok models]
  end

  context "with gemini" do
    let(:name) { "gemini" }
    let(:argv) { ["gemini", "-p", "", "--skip-trust"] }

    context "when signed in, which ends for want of input" do
      let(:answers) { { argv => result.call("", status: 42, stderr: "No input provided via stdin.\n") } }

      it { is_expected.to be_available }
      it { expect(availability.models).to eq(OpenLanes::Adapters::Gemini::MODELS) }
    end

    context "when signed out" do
      let(:answers) { { argv => result.call("", status: 41, stderr: "Please set an Auth method\n") } }

      it { expect(availability.reason).to eq("not signed in (run `gemini` and choose a sign-in method)") }
    end

    context "with an account the client refuses, which still exits 42" do
      let(:stderr) do
        "Error authenticating: IneligibleTierError: This client is no longer supported for Gemini Code Assist " \
          "for individuals. To continue, migrate.\n  ineligibleTiers: [\n"
      end
      let(:answers) { { argv => result.call("", status: 42, stderr:) } }

      it do
        expect(availability.reason)
          .to eq("account tier refused: This client is no longer supported for Gemini Code Assist for individuals")
      end
    end

    context "when signing in failed otherwise" do
      let(:answers) { { argv => result.call("", status: 42, stderr: "Error authenticating: token expired\n") } }

      it { expect(availability.reason).to eq("sign-in failed: token expired") }
    end

    context "when it fails some other way" do
      let(:answers) { { argv => result.call("", status: 52, stderr: "Warning\nYOLO mode is disabled\n") } }

      it { expect(availability.reason).to eq("`gemini` exited 52: YOLO mode is disabled") }
    end

    it_behaves_like "a probe that says it timed out", ["gemini", "-p", "", "--skip-trust"]
  end

  describe "an adapter that does not probe itself" do
    subject(:probe) { OpenLanes::Adapters::Mute.new.probe(runner: ScriptedProbeRunner.new(installed: ["mute"]), at:) }

    before { stub_const("OpenLanes::Adapters::Mute", Class.new(OpenLanes::Adapters::Base)) }

    it { expect { probe }.to raise_error(NotImplementedError, /must probe itself/) }
  end
end

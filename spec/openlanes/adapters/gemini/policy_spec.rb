# frozen_string_literal: true

RSpec.describe OpenLanes::Adapters::Gemini::Policy do
  subject(:policy) { described_class.new(denied_commands:, network:) }

  let(:denied_commands) { ["git push", "gh pr merge"] }
  let(:network) { false }

  describe "#to_toml" do
    subject(:toml) { policy.to_toml }

    it "denies each forbidden command by prefix, at the top of the user tier" do
      expect(toml).to include(<<~RULE)
        [[rule]]
        toolName = "run_shell_command"
        commandPrefix = ["git push", "gh pr merge"]
        denyMessage = "openlanes withholds this command"
        decision = "deny"
        priority = 999
      RULE
    end

    it "takes the question tool and the web tools away" do
      expect(toml).to include(%(toolName = ["ask_user", "google_web_search", "web_fetch"]))
    end

    context "with no command withheld and the network declared" do
      let(:denied_commands) { [] }
      let(:network) { true }

      it "keeps only the question tool away" do
        expect(toml.scan("[[rule]]").size).to eq(1)
      end

      it { is_expected.to include(%(toolName = ["ask_user"])) }
    end
  end

  describe "#path" do
    let(:policies) { Dir.mktmpdir("gemini-policies") }

    before { stub_const("#{described_class}::DIR", "#{policies}/nested") }

    after { FileUtils.rm_rf(policies) }

    it "writes the policy where it says" do
      expect(File.read(policy.path)).to eq(policy.to_toml)
    end

    it "does not write the same policy twice" do
      first = policy.path
      File.write(first, "kept")
      expect([policy.path, File.read(first)]).to eq([first, "kept"])
    end
  end
end

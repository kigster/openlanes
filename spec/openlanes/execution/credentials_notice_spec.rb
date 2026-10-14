# frozen_string_literal: true

RSpec.describe OpenLanes::Execution, ".credentials_notice" do
  subject(:notice) { described_class.credentials_notice }

  before { allow(OpenLanes::Execution::Executor).to receive(:foreign_credentials).and_return(names) }

  context "when no credential shadows the login" do
    let(:names) { [] }

    it { is_expected.to be_nil }
  end

  context "with one credential in the shell" do
    let(:names) { ["ANTHROPIC_API_KEY"] }

    it "names it, the failure it predicts, and the fix" do
      expect(notice).to include("ANTHROPIC_API_KEY is set in this shell", "401 API key is invalid",
        "unset ANTHROPIC_API_KEY")
    end
  end

  context "with two" do
    let(:names) { %w[ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN] }

    it "speaks of them in the plural" do
      expect(notice).to include("ANTHROPIC_API_KEY and CLAUDE_CODE_OAUTH_TOKEN are set", "with them rather")
    end
  end
end

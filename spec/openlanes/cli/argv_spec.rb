# frozen_string_literal: true

RSpec.describe OpenLanes::CLI::Argv do
  subject(:argv) { described_class.for(declared, values, defaults:, except:) }

  let(:declared) { OpenLanes::CLI::EngineCommand.options }
  let(:defaults) { OpenLanes::CLI::EngineCommand.default_params }
  let(:except) { [] }
  let(:values) { defaults.merge(jobs: "3", git_push: false, user_config: true, plan: "005,006", rescan: defaults[:rescan]) }

  it("types what differs from the defaults") { expect(argv).to contain_exactly("--jobs=3", "--no-git-push", "--user-config", "--plan=005,006") }

  context "with options left out" do
    let(:except) { %i[jobs plan] }

    it { expect(argv).to contain_exactly("--no-git-push", "--user-config") }
  end

  context "with a value that starts with a dash" do
    let(:values) { defaults.merge(prompt: "-x") }

    it("keeps it attached to its flag") { expect(argv).to eq(["--prompt=-x"]) }
  end

  context "with nothing typed" do
    let(:values) { defaults }

    it { expect(argv).to be_empty }
  end

  context "with an array option" do
    let(:declared) { [Dry::CLI::Option.new(:tags, type: :array)] }
    let(:values) { { tags: %w[a b] } }
    let(:defaults) { {} }

    it { expect(argv).to eq(["--tags=a,b"]) }
  end
end

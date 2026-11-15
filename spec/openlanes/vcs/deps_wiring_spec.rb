# frozen_string_literal: true

require "tmpdir"

# The `github` key reaches every class that talks to GitHub when it is built
# without a `github:` of its own: stubbing the key is enough to keep a spec
# off the network, without threading a fake through each constructor.
RSpec.describe "the github key through the container" do
  let(:fake) { Object.new }
  let(:root) { Dir.mktmpdir("deps-wiring") }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: root) }

  before { OpenLanes::Container.stub("github", fake) }
  after { FileUtils.rm_rf(root) }

  {
    "Vcs::Review"            => -> { OpenLanes::Vcs::Review.new },
    "Vcs::LabelSync"         => -> { OpenLanes::Vcs::LabelSync.new },
    "Vcs::LabelMigration"    => -> { OpenLanes::Vcs::LabelMigration.new },
    "Vcs::Publisher"         => -> { OpenLanes::Vcs::Publisher.new(root:) },
    "Lifecycle::Adoption"    => -> { OpenLanes::Lifecycle::Adoption.new(tree:, root:) },
    "Lifecycle::Resync::Prs" => -> { OpenLanes::Lifecycle::Resync::Prs.new(tree:, root:) }
  }.each do |name, build|
    it "hands #{name} the stubbed client" do
      expect(instance_exec(&build).instance_variable_get(:@github)).to be(fake)
    end
  end

  it "answers Vcs.github and Vcs.review from the container" do
    aggregate_failures do
      expect(OpenLanes::Vcs.github).to be(fake)
      expect(OpenLanes::Vcs.review.instance_variable_get(:@github)).to be(fake)
    end
  end

  it "still takes a client a caller passes in" do
    own = Object.new

    expect(OpenLanes::Vcs::Review.new(github: own).instance_variable_get(:@github)).to be(own)
  end
end

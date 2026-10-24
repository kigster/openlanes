# frozen_string_literal: true

RSpec.describe OpenLanes::Setup::CiDetector do
  subject(:found) { described_class.new(root).call }

  let(:root) { Dir.mktmpdir("openlanes-ci") }

  after { FileUtils.rm_rf(root) }

  def touch(name)
    path = File.join(root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")
  end

  {
    ".github/workflows/test.yaml" => :github_actions,
    ".circleci/config.yml"        => :circleci,
    "Jenkinsfile"                 => :jenkins,
    ".gitlab-ci.yml"              => :gitlab
  }.each do |path, provider|
    it "finds #{provider} from #{path}" do
      touch(path)
      expect(found).to eq([described_class::Found.new(provider:, path:)])
    end
  end

  it "finds buildkite from its folder" do
    FileUtils.mkdir_p(File.join(root, ".buildkite"))
    expect(found.map(&:provider)).to eq([:buildkite])
  end

  it "ignores a workflows folder with no workflow in it" do
    touch(".github/workflows/README.md")
    expect(found).to eq([])
  end

  it "reports several at once as a list" do
    touch(".github/workflows/ci.yml")
    touch("Jenkinsfile")
    expect(found.map(&:provider)).to eq(%i[github_actions jenkins])
  end

  it "is empty when there is none" do
    expect(found).to eq([])
  end
end

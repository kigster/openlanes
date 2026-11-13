# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe OpenLanes::Web::BranchDiff do
  let(:root) { Dir.mktmpdir("branch-diff") }
  let(:feature) { OpenLanes::Plans::Feature.parse("003.00-⭐️--tax-rule-dsl") }

  after { FileUtils.rm_rf(root) }

  def git(*) = Open3.capture2e("git", "-C", root, *).then { |out, status| status.success? ? out : raise(out) }

  before do
    git("init", "-q", "-b", "main")
    git("config", "user.email", "dev@example.com")
    git("config", "user.name", "Dev")
    File.write(File.join(root, "a.rb"), "one\n")
    git("add", ".")
    git("commit", "-qm", "base")
    git("checkout", "-qb", "someone/003.00-tax-rule-dsl")
    File.write(File.join(root, "a.rb"), "one\n#{"two\n" * 50}")
    git("commit", "-qam", "work")
  end

  it "diffs the plan's branch against the base, whoever's branch it is" do
    result = described_class.new(root: root, base: "main").call(feature)
    expect([result[:stat], result[:patch], result[:truncated]]).to match([/a\.rb \| 50 \+/, /\+two/, false])
  end

  it "cuts a patch over the cap and says so" do
    result = described_class.new(root: root, base: "main", max: 40).call(feature)
    expect([result[:patch].bytesize, result[:truncated]]).to eq([40, true])
  end

  it "answers an empty diff for a plan with no branch" do
    other = OpenLanes::Plans::Feature.parse("004.00-⭐️--other")
    expect(described_class.new(root: root, base: "main").call(other)).to eq(described_class::EMPTY)
  end
end

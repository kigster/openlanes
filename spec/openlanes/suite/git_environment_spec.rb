# frozen_string_literal: true

require "open3"
require "tmpdir"

# The suite runs from a pre-commit hook, where git exports the repository
# being committed to. spec_helper.rb drops those variables; this is the
# example that fails when it stops.
RSpec.describe "The suite's git environment" do
  it "carries none of the variables git exports to a hook" do
    locals, = Open3.capture2("git", "rev-parse", "--local-env-vars")

    expect((locals.split - %w[GIT_CONFIG_COUNT]) & ENV.keys).to be_empty
  end

  it "runs git in the directory it is given, not in a repository named by the caller" do
    Dir.mktmpdir do |dir|
      Open3.capture2e("git", "init", "-q", dir)
      top, = Open3.capture2("git", "-C", dir, "rev-parse", "--show-toplevel")

      expect(File.realpath(top.strip)).to eq(File.realpath(dir))
    end
  end
end

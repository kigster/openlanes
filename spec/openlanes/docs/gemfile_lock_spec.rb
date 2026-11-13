# frozen_string_literal: true

require "open3"

# Gemfile.lock records the gem's own version twice, and nothing rewrites it
# when lib/openlanes/version.rb is edited by hand. Version 4.0.1 was committed
# over a lockfile still saying 4.0.0, so every `bundle` run dirtied the
# lockfile in every checkout and worktree. `just bump <version>` edits both.
#
# This compares the two files as HEAD has them, not as they are on disk:
# Bundler quietly re-locks the file on disk before the first example runs, so
# reading it there would pass on exactly the commit this exists to refuse.
RSpec.describe "Gemfile.lock" do
  # @param path [String] a path relative to the repository root
  # @return [String, nil] the file as committed at HEAD, nil outside a git checkout
  def committed(path)
    out, status = Open3.capture2e("git", "-C", OpenLanes::Uml::GEM_ROOT, "show", "HEAD:#{path}")
    out if status.success?
  end

  let(:lockfile) { committed("Gemfile.lock") }
  let(:version) { committed("lib/openlanes/version.rb")&.[](/VERSION = "([^"]+)"/, 1) }

  it "is committed at the committed OpenLanes::VERSION; run `just bump <version>` when it is not" do
    skip "not a git checkout" unless lockfile && version

    locked = lockfile.scan(/^\s+openlanes \(([^)]+)\)$/).flatten

    expect(locked).not_to be_empty
    expect(locked.uniq).to eq([version])
  end
end

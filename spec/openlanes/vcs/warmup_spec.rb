# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Vcs::Warmup do
  subject(:warmup) { described_class.new(cache:, installer:) }

  let(:tmp) { Dir.mktmpdir("openlanes-warmup") }
  let(:cache) { File.join(tmp, "cache") }
  let(:calls) { [] }
  let(:succeeds) { true }
  # Stands in for bundler and npm: records the call, and for npm leaves a
  # node_modules behind the way `npm ci` would.
  let(:installer) do
    log = calls
    ok = succeeds
    lambda do |kind, dir, env|
      log << [kind, dir, env]
      FileUtils.mkdir_p(File.join(dir, "node_modules", "left-pad")) if ok && kind == :npm
      ok
    end
  end

  after { FileUtils.rm_rf(tmp) }

  def checkout(name, gemfile_lock: "GEM\n  rake (13.0)\n", package_lock: "{\"lockfileVersion\": 3}\n")
    File.join(tmp, name).tap do |path|
      FileUtils.mkdir_p(path)
      File.write(File.join(path, "Gemfile.lock"), gemfile_lock) if gemfile_lock
      File.write(File.join(path, "package-lock.json"), package_lock) if package_lock
    end
  end

  it "installs once for two worktrees whose lockfiles match, and shares the cache" do
    first = warmup.call(checkout("a"))
    second = warmup.call(checkout("b"))

    expect(calls.map(&:first)).to eq(%i[bundler npm])
    expect([first.installed, second.shared]).to eq([%i[bundler npm], %i[bundler npm]])
    expect(File.directory?(File.join(tmp, "b", "node_modules", "left-pad"))).to be(true)
  end

  it "leaves a node_modules that Prewarm cloned in, rather than running npm ci over it" do
    path = checkout("a", gemfile_lock: nil)
    FileUtils.mkdir_p(File.join(path, "node_modules", "cloned"))
    result = warmup.call(path)

    expect(calls).to be_empty
    expect(result.shared).to eq(%i[npm])
    expect(File.directory?(File.join(path, "node_modules", "cloned"))).to be(true)
  end

  it "points both worktrees' Bundler at the same cache entry" do
    a = checkout("a")
    b = checkout("b")
    [a, b].each { warmup.call(it) }
    entry = warmup.entry_for(:bundler, File.join(a, "Gemfile.lock"))

    expect([a, b].map { File.read(File.join(it, ".bundle", "config")) }.uniq).to eq(["---\nBUNDLE_PATH: #{entry.inspect}\n"])
    expect(calls.first.last).to eq("BUNDLE_PATH" => entry)
  end

  it "keeps the other settings in a worktree's .bundle/config" do
    path = checkout("a", package_lock: nil)
    FileUtils.mkdir_p(File.join(path, ".bundle"))
    File.write(File.join(path, ".bundle", "config"), "---\nBUNDLE_JOBS: \"4\"\nBUNDLE_PATH: \"vendor\"\n")
    warmup.call(path)

    expect(File.read(File.join(path, ".bundle", "config"))).to match(/\A---\nBUNDLE_PATH: ".+cache.+"\nBUNDLE_JOBS: "4"\n\z/)
  end

  it "gives a changed lockfile a new cache entry" do
    warmup.call(checkout("a"))
    changed = warmup.call(checkout("b", gemfile_lock: "GEM\n  rake (13.1)\n"))

    expect([changed.installed, changed.shared]).to eq([%i[bundler], %i[npm]])
    expect(Dir.children(File.join(cache, "bundler")).grep_v(/\.lock\z/).size).to eq(2)
  end

  it "leaves a checkout with no lockfile alone" do
    path = checkout("bare", gemfile_lock: nil, package_lock: nil)
    result = warmup.call(path)

    expect([result.untouched?, calls, Dir.children(path)]).to eq([true, [], []])
  end

  context "when the installer fails" do
    let(:succeeds) { false }

    it "reports the failure instead of raising, and installs again next time" do
      first = warmup.call(checkout("a"))
      warmup.call(checkout("b"))

      expect(first.ok?).to be(false)
      expect(first.failures.keys).to eq(%i[bundler npm])
      expect(calls.size).to eq(4)
    end
  end

  it "reports an error from the filesystem instead of raising" do
    path = checkout("a", package_lock: nil)
    FileUtils.mkdir_p(File.join(tmp, "cache"))
    File.write(File.join(cache, "bundler"), "not a directory")

    expect(warmup.call(path).failures.keys).to eq(%i[bundler])
  end

  it "keys an entry by the lockfile's contents" do
    path = checkout("a")
    expect(described_class.digest(File.join(path, "Gemfile.lock"))).to match(/\A\h{16}\z/)
  end
end

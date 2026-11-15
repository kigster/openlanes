# frozen_string_literal: true

require "tmpdir"

RSpec.describe OpenLanes::Vcs::Warmup do
  subject(:warmup) { described_class.new(cache:, runner:) }

  let(:tmp) { Dir.mktmpdir("openlanes-warmup") }
  let(:cache) { File.join(tmp, "cache") }
  let(:calls) { [] }
  let(:succeeds) { true }
  let(:satisfied) { false }
  # Stands in for bundler and npm: records each install, answers `bundle
  # check` with `satisfied`, and leaves behind what a real install would.
  let(:runner) do
    log = calls
    ok = succeeds
    check = satisfied
    lambda do |argv, dir, env|
      next check if argv == %w[bundle check]

      log << [argv.first, dir, env]
      next ok unless ok

      FileUtils.mkdir_p(argv.first == "npm" ? File.join(dir, "node_modules", "left-pad") : File.join(env["BUNDLE_PATH"], "rake"))
      true
    end
  end

  after { FileUtils.rm_rf(tmp) }

  def git(path, *) = system("git", "-C", path, *, out: File::NULL, err: File::NULL)

  def checkout(name, gemfile_lock: "GEM\n  rake (13.0)\n", package_lock: "{\"lockfileVersion\": 3}\n", ignore: "/.bundle/\n/node_modules/\n")
    File.join(tmp, name).tap do |path|
      FileUtils.mkdir_p(path)
      git(path, "init", "-q")
      File.write(File.join(path, ".gitignore"), ignore)
      File.write(File.join(path, "Gemfile.lock"), gemfile_lock) if gemfile_lock
      File.write(File.join(path, "package-lock.json"), package_lock) if package_lock
    end
  end

  it "installs once for two worktrees whose lockfiles match, and clones the result into the second" do
    first = warmup.call(checkout("a"))
    second = warmup.call(checkout("b"))

    expect(calls.map(&:first)).to eq(%w[bundle npm])
    expect([first.installed, second.shared]).to eq([%i[bundler npm], %i[bundler npm]])
    expect(File.directory?(File.join(tmp, "b", "node_modules", "left-pad"))).to be(true)
    expect(File.directory?(File.join(tmp, "b", ".bundle", "openlanes-gems", "rake"))).to be(true)
  end

  it "leaves a node_modules that Prewarm cloned in, rather than running npm ci over it" do
    path = checkout("a", gemfile_lock: nil)
    FileUtils.mkdir_p(File.join(path, "node_modules", "cloned"))
    result = warmup.call(path)

    expect(calls).to be_empty
    expect(result.shared).to eq(%i[npm])
    expect(File.directory?(File.join(path, "node_modules", "cloned"))).to be(true)
  end

  it "points each worktree's Bundler at a copy of its own, never at the cache" do
    a = checkout("a", package_lock: nil)
    warmup.call(a)
    target = File.join(a, ".bundle", "openlanes-gems")

    expect(File.read(File.join(a, ".bundle", "config"))).to eq("---\nBUNDLE_PATH: #{target.inspect}\n")
    expect(calls.first.last).to eq("BUNDLE_PATH" => target)
  end

  it "keeps a worktree's edit to an installed gem out of the next worktree" do
    a = checkout("a", package_lock: nil)
    warmup.call(a)
    File.write(File.join(a, ".bundle", "openlanes-gems", "rake", "evil.rb"), "system('true')")
    b = checkout("b", package_lock: nil)
    warmup.call(b)

    expect(File.exist?(File.join(b, ".bundle", "openlanes-gems", "rake", "evil.rb"))).to be(false)
  end

  it "keeps the other settings in a worktree's .bundle/config" do
    path = checkout("a", package_lock: nil)
    FileUtils.mkdir_p(File.join(path, ".bundle"))
    File.write(File.join(path, ".bundle", "config"), "---\nBUNDLE_JOBS: \"4\"\nBUNDLE_PATH: \"vendor\"\n")
    warmup.call(path)

    expect(File.read(File.join(path, ".bundle", "config"))).to match(/\A---\nBUNDLE_PATH: ".+openlanes-gems"\nBUNDLE_JOBS: "4"\n\z/)
  end

  it "skips Bundler when git would publish .bundle/config" do
    path = checkout("a", package_lock: nil, ignore: "")
    result = warmup.call(path)

    expect([result.skipped, calls, File.exist?(File.join(path, ".bundle"))]).to eq([{ bundler: "git does not ignore .bundle/openlanes-gems" }, [], false])
  end

  it "skips Bundler when .bundle/config is a symlink" do
    path = checkout("a", package_lock: nil)
    outside = File.join(tmp, "outside")
    File.write(outside, "keep me")
    FileUtils.mkdir_p(File.join(path, ".bundle"))
    File.symlink(outside, File.join(path, ".bundle", "config"))

    expect(warmup.call(path).skipped).to eq(bundler: ".bundle/config is a symlink")
    expect(File.read(outside)).to eq("keep me")
  end

  context "when bundle check already passes" do
    let(:satisfied) { true }

    it "installs nothing for Bundler" do
      result = warmup.call(checkout("a", package_lock: nil))
      expect([result.skipped, calls]).to eq([{ bundler: "already satisfied" }, []])
    end
  end

  describe "against a base branch" do
    def committed(name)
      checkout(name, package_lock: nil).tap do |path|
        git(path, "add", "-A")
        git(path, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "base")
      end
    end

    it "warms when the dependency files match the base" do
      expect(warmup.call(committed("a"), base: "HEAD").installed).to eq(%i[bundler])
    end

    it "skips a kind whose lockfile the branch changed" do
      path = committed("a")
      File.write(File.join(path, "Gemfile.lock"), "GEM\n  rake (99.0)\n")

      expect(warmup.call(path, base: "HEAD").skipped).to eq(bundler: "Gemfile.lock differs from HEAD")
    end

    it "skips a kind whose Gemfile the branch added" do
      path = committed("a")
      File.write(File.join(path, "Gemfile"), "system('git push')\n")

      expect([warmup.call(path, base: "HEAD").skipped, calls]).to eq([{ bundler: "Gemfile differs from HEAD" }, []])
    end

    # The Gemfile says `gemspec`; bundle check would evaluate the edited file.
    it "skips, running nothing, when the branch edited a gemspec and left the Gemfile alone" do
      path = committed("a")
      File.write(File.join(path, "a.gemspec"), "system('git push origin HEAD')\n")

      expect([warmup.call(path, base: "HEAD").skipped, calls]).to eq([{ bundler: "the checkout differs from HEAD" }, []])
    end

    it "skips when a tracked file the Gemfile may load differs from the base" do
      path = committed("a")
      File.write(File.join(path, "a.gemspec"), "# base\n")
      git(path, "add", "a.gemspec")

      expect(warmup.call(path, base: "HEAD").skipped).to eq(bundler: "the checkout differs from HEAD")
    end
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

    expect([result.untouched?, calls]).to eq([true, []])
  end

  context "when the installer fails" do
    let(:succeeds) { false }

    it "reports the failure instead of raising, and installs again next time" do
      first = warmup.call(checkout("a"))
      warmup.call(checkout("b"))

      expect(first.ok?).to be(false)
      expect(first.failures.keys).to eq(%i[bundler npm])
      expect(calls.size).to eq(4)
      expect(File.exist?(File.join(tmp, "a", ".bundle", "config"))).to be(false)
    end
  end

  it "reports an error from the filesystem instead of raising" do
    path = checkout("a", package_lock: nil)
    FileUtils.mkdir_p(File.join(tmp, "cache"))
    File.write(File.join(cache, "bundler"), "not a directory")

    expect(warmup.call(path).failures.keys).to eq(%i[bundler])
  end

  it "runs npm without lifecycle scripts" do
    expect(described_class::KINDS.find { it.name == :npm }.install).to include("--ignore-scripts")
  end

  it "keys an entry by the lockfile's contents" do
    path = checkout("a")
    expect(described_class.digest(File.join(path, "Gemfile.lock"))).to match(/\A\h{16}\z/)
  end
end

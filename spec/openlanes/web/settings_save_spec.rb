# frozen_string_literal: true

require "tmpdir"

# Real git throughout: a main checkout whose `origin` is a bare repository,
# and a second clone standing in for everybody else pushing to main.
RSpec.describe OpenLanes::Web::SettingsSave, :origin do
  let(:tmp) { Dir.mktmpdir("settings-save") }
  let(:main) { File.join(tmp, "main") }
  let(:origin) { File.join(tmp, "origin.git") }
  let(:file) { File.join(main, OpenLanes::Config::FILE) }
  let(:boundary) { class_double(OpenLanes::Execution::Boundary, sanction: nil) }
  let!(:upstream) do
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "jobs: 2\n")
    publish_with_origin(main, tmp)
  end

  after { FileUtils.rm_rf(tmp) }

  def save(values, if_match: OpenLanes::Web::Settings.etag(main))
    described_class.new(root: main, boundary:).call(values:, if_match:)
  end

  def origin_main = git!(origin, "rev-parse", "main")
  def head = git!(main, "rev-parse", "HEAD")

  it "writes nothing and commits nothing when the values match the file" do
    before = [head, origin_main, File.read(file)]
    outcome = save({ "jobs" => 2, "merge" => { "by" => nil } })

    expect(outcome.to_h).to eq(status: 200, body: { changed: false })
    expect([head, origin_main, File.read(file)]).to eq(before)
  end

  it "writes the full file, commits it alone and pushes main after sanctioning the push" do
    File.write(File.join(main, "app.rb"), "edited and left alone\n")
    outcome = save({ "jobs" => 4 })

    expect(outcome.status).to eq(200)
    expect(outcome.body).to include(changed: true, commit: head, etag: OpenLanes::Web::Settings.etag(main))
    expect(origin_main).to eq(head)
    expect(OpenLanes::Config.load(main).jobs).to eq(4)
    expect(File.read(file)).to eq(OpenLanes::Config.load(main).to_yaml)
    expect(git!(main, "show", "--name-only", "--format=", "HEAD")).to eq(OpenLanes::Config::FILE)
    expect(git!(main, "log", "-1", "--format=%s")).to eq("Update .openlanes/config.yml from the settings page")
    expect(git!(main, "status", "--porcelain")).to eq("M app.rb")
    expect(boundary).to have_received(:sanction).with(main, "origin", "main")
  end

  it "fast-forwards main to origin/main before committing" do
    theirs = commit_file(upstream, "other.txt", "from upstream\n")
    git!(upstream, "push", "-q", "origin", "main")
    save({ "jobs" => 5 })

    expect(git!(main, "rev-parse", "HEAD~1")).to eq(theirs)
    expect(origin_main).to eq(head)
  end

  context "when a refusal applies" do
    def expect_untouched(outcome, refusal)
      expect(outcome.status).to eq(409)
      expect(outcome.body).to include(refusal:, reason: a_string_matching(/\S/))
      expect(boundary).not_to have_received(:sanction)
    end

    it "refuses when the main checkout is not on main" do
      git!(main, "checkout", "-q", "-b", "other")
      before = [head, origin_main, File.read(file)]
      expect_untouched(save({ "jobs" => 3 }), "not_on_main")
      expect([head, origin_main, File.read(file)]).to eq(before)
    end

    it "refuses when .openlanes/config.yml has uncommitted edits" do
      File.write(file, "jobs: 9\n")
      before = [head, origin_main]
      expect_untouched(save({ "jobs" => 3 }), "dirty_config")
      expect([head, origin_main, File.read(file)]).to eq(before + ["jobs: 9\n"])
    end

    it "refuses a stale etag" do
      before = [head, origin_main, File.read(file)]
      expect_untouched(save({ "jobs" => 3 }, if_match: "nope"), "stale_etag")
      expect([head, origin_main, File.read(file)]).to eq(before)
    end

    it "refuses when origin/main holds a newer .openlanes/config.yml" do
      commit_file(upstream, OpenLanes::Config::FILE, "jobs: 7\n")
      git!(upstream, "push", "-q", "origin", "main")
      before = [head, File.read(file)]
      expect_untouched(save({ "jobs" => 3 }), "stale_etag")
      expect([head, File.read(file)]).to eq(before)
    end

    # Issue 251: only the path this checkout uses was compared, so a save
    # into a root with no config fast-forwarded onto the legacy file
    # origin/main had just added, and overwrote it with the page's defaults.
    it "refuses when origin/main added a config at the other path" do
      git!(main, "rm", "-q", OpenLanes::Config::FILE)
      git!(main, "commit", "-q", "-m", "drop the config")
      git!(main, "push", "-q", "origin", "main")
      git!(upstream, "pull", "-q", "origin", "main")
      commit_file(upstream, OpenLanes::Project::LEGACY_FILE, "jobs: 7\nproject: Theirs\n")
      git!(upstream, "push", "-q", "origin", "main")
      before = head
      outcome = save({ "jobs" => 3 })

      expect_untouched(outcome, "stale_etag")
      expect(outcome.body[:reason]).to eq("origin/main holds a newer .openlanes.yml; pull and reload")
      expect([head, git!(origin, "show", "main:#{OpenLanes::Project::LEGACY_FILE}")]).to eq([before, "jobs: 7\nproject: Theirs"])
    end

    it "answers 409 with the both-files message when the root holds both files" do
      File.write(File.join(main, OpenLanes::Project::LEGACY_FILE), "jobs: 5\n")
      before = [head, origin_main, File.read(file)]
      outcome = save({ "jobs" => 3 })

      expect_untouched(outcome, "both_files")
      expect(outcome.body[:reason]).to eq("both .openlanes/config.yml and .openlanes.yml exist; keep one and remove the other")
      expect([head, origin_main, File.read(file)]).to eq(before)
    end

    it "refuses when main cannot fast-forward to origin/main" do
      commit_file(upstream, "theirs.txt", "theirs\n")
      git!(upstream, "push", "-q", "origin", "main")
      commit_file(main, "mine.txt", "mine\n")
      before = [head, origin_main, File.read(file)]
      expect_untouched(save({ "jobs" => 3 }), "cannot_fast_forward")
      expect([head, origin_main, File.read(file)]).to eq(before)
    end

    it "refuses when origin cannot be fetched" do
      git!(main, "remote", "set-url", "origin", File.join(tmp, "missing.git"))
      expect_untouched(save({ "jobs" => 3 }), "cannot_fast_forward")
    end

    it "takes the commit back when the push is refused" do
      hook = File.join(origin, "hooks", "pre-receive")
      File.write(hook, "#!/bin/sh\nexit 1\n")
      File.chmod(0o755, hook)
      before = [head, origin_main, File.read(file)]
      outcome = save({ "jobs" => 3 })

      expect(outcome.to_h).to include(status: 409, body: include(refusal: "push_failed"))
      expect([head, origin_main, File.read(file)]).to eq(before)
      expect(git!(main, "status", "--porcelain")).to eq("")
    end

    it "restores the file and answers 409 when the commit itself fails" do
      hook = File.join(main, ".git", "hooks", "pre-commit")
      File.write(hook, "#!/bin/sh\necho 'secret hook output' >&2\nexit 1\n")
      File.chmod(0o755, hook)
      before = [head, origin_main, File.read(file)]
      outcome = save({ "jobs" => 3 })

      expect_untouched(outcome, "commit_failed")
      expect(outcome.body[:reason]).not_to include(main, "secret hook output")
      expect([head, origin_main, File.read(file)]).to eq(before)
      expect(git!(main, "status", "--porcelain")).to eq("")
    end
  end

  it "creates the .openlanes folder for a project that has no config file yet" do
    git!(main, "rm", "-q", OpenLanes::Config::FILE)
    git!(main, "commit", "-q", "-m", "drop the config")
    git!(main, "push", "-q", "origin", "main")
    outcome = save({ "jobs" => 4 })

    expect([outcome.status, File.read(file), origin_main])
      .to eq([200, OpenLanes::Config.load(main).to_yaml, head])
  end

  context "when the project still has the legacy file" do
    let(:legacy) { File.join(main, OpenLanes::Project::LEGACY_FILE) }

    around do |example|
      OpenLanes::Project.reset_notices!
      example.run
    ensure
      OpenLanes::Project.reset_notices!
    end

    before do
      git!(main, "mv", OpenLanes::Config::FILE, OpenLanes::Project::LEGACY_FILE)
      git!(main, "commit", "-q", "-m", "back to the legacy name")
      git!(main, "push", "-q", "origin", "main")
    end

    it "saves into the legacy file and never writes a second one" do
      outcome = nil
      expect { outcome = save({ "jobs" => 4 }) }.to output(/config move/).to_stderr

      expect([outcome.status, File.exist?(file), OpenLanes::Config.load(main).jobs])
        .to eq([200, false, 4])
      expect(git!(main, "show", "--name-only", "--format=", "HEAD")).to eq(OpenLanes::Project::LEGACY_FILE)
      expect(git!(main, "status", "--porcelain")).to eq("")
    end

    it "names the legacy file in the commit subject" do
      expect { save({ "jobs" => 4 }) }.to output.to_stderr
      expect(git!(main, "log", "-1", "--format=%s")).to eq("Update .openlanes.yml from the settings page")
    end

    it "strips the legacy file's name from a parser refusal, as it does the new one's" do
      outcome = nil
      expect { outcome = save({ "redis_url" => "redis://:pw@host:6379/0" }) }.to output.to_stderr

      expect(outcome.to_h).to eq(status: 422,
        body: { errors: [{ path:    ["redis_url"],
                           message: "redis_url carries a password; this file is committed, so set the REDIS_URL environment variable instead" }] })
    end
  end

  it "refuses an invalid value before any write" do
    before = [head, origin_main, File.read(file)]
    outcome = save({ "jobs" => "many", "merge" => { "by" => "robot" } })

    expect(outcome.status).to eq(422)
    expect(outcome.body[:errors].map { it[:path] }).to include(["jobs"])
    expect([head, origin_main, File.read(file)]).to eq(before)
  end
end

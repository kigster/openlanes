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
    FileUtils.mkdir_p(main)
    File.write(File.join(main, OpenLanes::Config::FILE), "jobs: 2\n")
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

    it "refuses when .openlanes.yml has uncommitted edits" do
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

    it "refuses when origin/main holds a newer .openlanes.yml" do
      commit_file(upstream, OpenLanes::Config::FILE, "jobs: 7\n")
      git!(upstream, "push", "-q", "origin", "main")
      before = [head, File.read(file)]
      expect_untouched(save({ "jobs" => 3 }), "stale_etag")
      expect([head, File.read(file)]).to eq(before)
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
  end

  it "refuses an invalid value before any write" do
    before = [head, origin_main, File.read(file)]
    outcome = save({ "jobs" => "many", "merge" => { "by" => "robot" } })

    expect(outcome.status).to eq(422)
    expect(outcome.body[:errors].map { it[:path] }).to include(["jobs"])
    expect([head, origin_main, File.read(file)]).to eq(before)
  end
end

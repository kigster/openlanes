# frozen_string_literal: true

require "open3"

# Plan 005 end to end: a pull request through its review labels, and the
# engine reading the verdict back. Real git, a real `.plans` tree, the real
# `exe/openlanes`, and real `gh` calls, answered by the fake `gh` put first
# on PATH: the only stand-in, since nothing here may reach GitHub.
RSpec.describe "Review labels, end to end", :tree do
  let(:repo) { File.dirname(plans_root) }
  let(:origin) { Dir.mktmpdir("openlanes-origin") }
  let(:worktrees) { Dir.mktmpdir("openlanes-worktrees") }
  let(:fake) { Dir.mktmpdir("openlanes-fake-gh") }
  let(:gh_state) { File.join(fake, "state.json") }
  let(:gh_log) { File.join(fake, "argv.log") }
  let(:exe) { File.expand_path("../../exe/openlanes", __dir__) }
  let(:fake_gh_dir) { File.expand_path("../support/fake_gh", __dir__) }
  let(:tree) { OpenLanes::Plans::Tree.new(dir: plans_root) }
  let(:plan_md) { "# Plan\n\n## U1\n\nBuild it.\n\n## How to test\n\n- Open the page and press Go.\n" }
  let(:files) { { "spec.md" => spec_body, "plan.md" => plan_md, "pull-requests.md" => "# Pull Requests\n" } }
  let(:env) do
    { "PATH" => "#{fake_gh_dir}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH")}",
      "FAKE_GH_RUBY" => RbConfig.ruby, "FAKE_GH_STATE" => gh_state, "FAKE_GH_LOG" => gh_log, "NO_COLOR" => "1" }
  end

  def git(*args, dir: repo) = system("git", "-C", dir, *args, out: File::NULL, err: File::NULL) || raise("git #{args.join(" ")} failed")
  def gh = JSON.parse(File.read(gh_state))
  def labels(number) = gh.dig("prs", number.to_s, "labels")
  def argv = File.readlines(gh_log).map { JSON.parse(it) }
  def plan(ordinal) = tree.reload.find(ordinal)

  def edit_gh
    data = gh
    yield data
    File.write(gh_state, JSON.generate(data))
  end

  # `exe/openlanes`, as a person or hansolo types it, in the project.
  def openlanes(*)
    out, err, status = Open3.capture3(env, RbConfig.ruby, exe, *, chdir: repo)
    [out, err, status.exitstatus]
  end

  around do |example|
    saved = ENV.to_h.slice(*env.keys)
    env.each { |key, value| ENV[key] = value }
    example.run
  ensure
    saved.each { |key, value| ENV[key] = value }
    (env.keys - saved.keys).each { ENV.delete(it) }
  end

  before do
    plans do |t|
      t.plan("001.00", :building, "rejected-one", files:)
      t.plan "002.00", :in_review, "merged-one", files: files.except("pull-requests.md"), prs: [t.open(41, "Merged one")]
      t.plan "003.00", :in_review, "open-one", files: files.except("pull-requests.md"), prs: [t.open(42, "Open one")]
    end
    git("init", "-q", "--initial-branch=main")
    git("config", "user.email", "ada@example.com")
    git("config", "user.name", "Ada")
    git("add", "-A")
    git("commit", "-qm", "initial")
    git("init", "-q", "--bare", dir: origin)
    git("remote", "add", "origin", origin)
    git("push", "-q", "origin", "main")

    blank = { "url" => "", "branch" => "", "merged_at" => nil, "labels" => [], "checks" => [], "comments" => [] }
    File.write(gh_state,
      JSON.generate("next" => 1,
        "labels" => [],
        "prs" => {
          "41" => blank.merge("title" => "Merged one", "state" => "MERGED", "merged_at" => "2026-10-14T10:00:00Z"),
          "42" => blank.merge("title" => "Open one", "state" => "OPEN", "labels" => %w[ready-to-merge])
        }))
  end

  after { [origin, worktrees, fake].each { FileUtils.rm_rf(it) } }

  # The harness's half: publish the build the way a round does, through the
  # runner, which records the pull request the folder's 🟢 is judged by.
  def publish
    runner = OpenLanes::Engine::Runner.new(tree:,
      executor:  ->(*) { raise "no agent runs here" },
      isolation: :worktree,
      worktree:  OpenLanes::Vcs::Worktree.new(root: repo, dir: worktrees, user: "tester", seeder: nil),
      publisher: OpenLanes::Vcs::Publisher.new(root: repo, dry_run: false))
    subject = plan("001.00")
    checkout = runner.worktree.checkout_for(subject.feature)
    File.write(File.join(checkout.path, "go.rb"), "puts :go\n")
    task = OpenLanes::Engine::Runner::Task.new(agent: OpenLanes::Agents::Registry.new.find("luke-backend"),
      subject:,
      root: checkout.path,
      checkout:,
      round: 1)
    runner.publish(task, subject)
  end

  # The engine's half: `openlanes start` in human mode, its clock moved on
  # 15 s. leah handles only ⚪️, so no agent starts: what moves is the watch.
  def watch_once
    clock = [0.0]
    runner = OpenLanes::Engine::Runner.new(tree:,
      executor: ->(*) { raise "no agent runs here" },
      agents:   OpenLanes::Agents::Registry.new.only("leah-researcher"),
      sleeper:  ->(_) {})
    dispatcher = OpenLanes::Engine::Dispatcher.new(runner:,
      sleeper: ->(_) {},
      stay: true,
      watch: OpenLanes::Engine::PrWatch.new(github: OpenLanes::Vcs::GitHub.new, clock: -> { clock.first }))
    dispatcher.tick
    clock[0] = 15.0
    dispatcher.tick
    dispatcher.instance_variable_get(:@watching)&.join
    dispatcher.tick
    dispatcher
  end

  # One story, told in the order it happens; split up, each part would have
  # to rebuild everything before it.
  it "takes a pull request from ready-for-review to a rejection the engine acts on" do # rubocop:disable RSpec/ExampleLength
    publication = publish
    number = publication.url[/\d+\z/]

    aggregate_failures "the publisher opens it with ready-for-review and its How to test" do
      expect(publication.label_error).to be_nil
      expect(labels(number)).to eq(%w[ready-for-review])
      expect(plan("001.00").pull_requests.map(&:url)).to eq([publication.url])
    end
    plan("001.00").machine.promote!(:ready_for_review)

    _, _, status = openlanes("review", number, "review-in-progress")
    aggregate_failures "hansolo starts" do
      expect(status).to eq(0)
      expect(labels(number)).to eq(%w[review-in-progress])
    end

    edit_gh { it["prs"][number]["checks"] = [{ "name" => "rspec", "state" => "FAILURE", "bucket" => "fail" }] }
    _, err, status = openlanes("review", number, "ready-to-merge")
    aggregate_failures "no passing verdict over red CI" do
      expect(status).not_to eq(0)
      expect(err).to include("CI is red")
      expect(labels(number)).to eq(%w[review-in-progress])
    end

    _, _, status = openlanes("review", number, "review-rejected")
    aggregate_failures "a rejection is accepted" do
      expect(status).to eq(0)
      expect(labels(number)).to eq(%w[review-rejected])
    end

    edit_gh do |data|
      data["prs"][number]["comments"] = [{ "author" => { "login" => "octo" }, "body" => "Go does nothing", "url" => "c1" }]
    end
    dispatcher = watch_once
    mail = OpenLanes::Plans::Mailbox.new(dir: plan("001.00").feature.path).messages

    aggregate_failures "the engine reads the verdicts back" do
      expect(plan("001.00").status.key).to eq(:rejected)
      expect(mail.map(&:to)).to include("luke-backend", "rey-frontend")
      expect(mail.first.body).to include("Go does nothing")
      expect(plan("002.00").status.key).to eq(:approved)
      expect(dispatcher.board.waiting_on).to eq("003.00" => [42])
      expect(OpenLanes::Presentation::Reporter.new(tree: tree.reload, waiting_on: dispatcher.board.waiting_on).render)
        .to include("waiting on you: PR #42")
    end

    expect(argv.flatten).not_to include("--force")
  end

  it "refuses to open a pull request whose plan.md has no How to test" do
    File.write(File.join(plan("001.00").feature.path, "plan.md"), "# Plan\n\n## U1\n")
    publication = publish

    aggregate_failures do
      expect(publication.refusal).to include("## How to test")
      expect(gh["prs"].keys).to eq(%w[41 42])
    end
  end
end

# frozen_string_literal: true

require "fileutils"
require "open3"
require "rack/test"
require "tmpdir"

# The Worktrees page's three reads, against a real repository with real
# worktrees. Only `gh` is a double: the seam the suite never lets out.
RSpec.describe OpenLanes::Web::Worktrees do
  let(:tmp) { File.realpath(Dir.mktmpdir("worktrees")) }
  let(:root) { File.join(tmp, "main") }
  let(:plans) { File.join(root, ".plans") }
  let(:plan_dir) { File.join(plans, "003.00-⭐️--tax-rule-dsl") }
  let(:built) { File.join(tmp, "wt", "003.00-tax-rule-dsl") }
  let(:loose) { File.join(tmp, "wt", "scratch") }
  let(:github) { instance_double(OpenLanes::Vcs::GitHub) }
  let(:service) { described_class.new(root:, plans_dir: plans, repo: "github.com/acme/widgets", github:, working: ->(o) { o == "003.00" }) }

  after { FileUtils.rm_rf(tmp) }

  def git(dir, *) = Open3.capture2e("git", "-C", dir, *).then { |out, status| status.success? ? out : raise(out) }

  before do
    FileUtils.mkdir_p(plan_dir)
    git(root, "init", "-q", "-b", "main")
    git(root, "config", "user.email", "dev@example.com")
    git(root, "config", "user.name", "Dev")
    File.write(File.join(root, "a.rb"), "one\n")
    File.write(File.join(plan_dir, "spec.md"), "# Tax rule DSL\n")
    File.write(File.join(plan_dir, "pull-requests.md"),
      OpenLanes::Plans::PullRequests.table([
                                             { number: 7, title: "Add the DSL", url: "https://github.com/acme/widgets/pull/7", state: "open" },
                                             { number: 8, title: "Fix the DSL", url: "https://github.com/acme/widgets/pull/8", state: "merged" },
                                             { number: 9, title: "Docs", url: "https://github.com/acme/widgets/pull/9", state: "open" },
                                             { number: 10, title: "Tests", url: "https://github.com/acme/widgets/pull/10", state: "open" },
                                           ]))
    git(root, "add", ".")
    git(root, "commit", "-qm", "base")
    git(root, "worktree", "add", "-q", "-b", "kig/003.00-tax-rule-dsl", built)
    File.write(File.join(built, "a.rb"), "one\ntwo\n")
    git(built, "commit", "-qam", "work")
    File.write(File.join(built, "b.rb"), "new\n")
    git(root, "worktree", "add", "-q", "-b", "scratch", loose)
  end

  def by_branch(branch) = service.list.find { it[:branch] == branch }

  it "lists every worktree but the main checkout, with its plan, state and git status" do
    expect(service.list.map { it[:branch] }).to eq(%w[kig/003.00-tax-rule-dsl scratch])
    row = by_branch("kig/003.00-tax-rule-dsl")
    expect(row).to include(id: described_class.id_for(built), path: built, modified: ["?? b.rb"], lines: { added: 1, removed: 0 })
    expect(row[:plan]).to include(ordinal: "003.00", title: "Tax Rule DSL", status: "planned", working: true)
    expect(by_branch("scratch")).to include(plan: nil, modified: [], lines: { added: 0, removed: 0 })
  end

  it "counts lines against main from the files on disk, so uncommitted edits count too" do
    File.write(File.join(built, "a.rb"), "two\nthree\nfour\n")
    expect(by_branch("kig/003.00-tax-rule-dsl")[:lines]).to eq(added: 3, removed: 1)
  end

  it "diffs a worktree's branch against main, with a compare link on GitHub" do
    result = service.diff(described_class.id_for(built))
    expect(result).to include(base: "main", truncated: false, compare_url: "https://github.com/acme/widgets/compare/main...kig/003.00-tax-rule-dsl")
    expect([result[:stat], result[:patch]]).to match([/a\.rb \| 1 \+/, /\+two/])
  end

  it "gives no compare link off GitHub" do
    other = described_class.new(root:, plans_dir: plans, repo: "gitlab.com/acme/widgets")
    expect(other.diff(described_class.id_for(built))[:compare_url]).to be_nil
  end

  it "lists the plan's pull requests, each with its CI as one word" do
    allow(github).to receive(:checks).with(number: 7).and_return([{ name: "a", bucket: "pass" }, { name: "b", bucket: "fail" }])
    allow(github).to receive(:checks).with(number: 8).and_return([{ name: "a", bucket: "pass" }, { name: "b", bucket: "skipping" }])
    allow(github).to receive(:checks).with(number: 9).and_return([{ name: "a", bucket: "pending" }])
    allow(github).to receive(:checks).with(number: 10).and_raise(OpenLanes::Error, "gh is down")
    pulls = service.pulls(described_class.id_for(built))
    expect(pulls.map { it.values_at(:number, :title, :ci) }).to eq([[7, "Add the DSL", "fail"], [8, "Fix the DSL", "pass"], [9, "Docs", "pending"], [10, "Tests", "unknown"]])
    expect(pulls.first[:url]).to eq("https://github.com/acme/widgets/pull/7")
  end

  it "says none for a pull request with no checks, and lists nothing for a worktree with no plan" do
    allow(github).to receive(:checks).and_return([])
    expect(service.pulls(described_class.id_for(built)).map { it[:ci] }.uniq).to eq(["none"])
    expect(service.pulls(described_class.id_for(loose))).to eq([])
  end

  it "refuses an id that names no worktree" do
    expect { service.diff("nope") }.to raise_error(described_class::NotFound, /no worktree nope/)
  end

  describe "the routes" do
    include Rack::Test::Methods

    let(:context) do
      OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(OpenLanes::Live.memory_store),
        keys: OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb"),
        plans_dir: plans,
        url: "redis://localhost:6379/3",
        dist: File.join(tmp, "dist"))
    end
    let(:app) { OpenLanes::Web.app(context) }

    def body = JSON.parse(last_response.body)

    before do
      header "Host", "127.0.0.1:11100"
      allow(OpenLanes::Vcs::GitHub).to receive(:new).and_return(github)
      allow(github).to receive(:checks).and_return([{ name: "a", bucket: "pass" }])
    end

    it "answers the list, a diff and the pull requests" do
      get "/api/worktrees"
      expect(body["worktrees"].map { it["branch"] }).to eq(%w[kig/003.00-tax-rule-dsl scratch])
      expect(body.dig("worktrees", 0, "plan", "working")).to be(false)

      id = described_class.id_for(built)
      get "/api/worktrees/#{id}/diff"
      expect(body["compare_url"]).to end_with("main...kig/003.00-tax-rule-dsl")

      get "/api/worktrees/#{id}/pulls"
      expect(body["pulls"].map { it["ci"] }.uniq).to eq(["pass"])
    end

    it "answers 404 for an unknown worktree" do
      get "/api/worktrees/nope/pulls"
      expect([last_response.status, body["error"]]).to eq([404, "there is no worktree nope"])
    end
  end
end

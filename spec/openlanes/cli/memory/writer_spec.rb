# frozen_string_literal: true

# `memory inbox`, `approve`, `promote` and `scan`: the deliverable goes to
# STDOUT, progress and refusals to STDERR, and `promote -n` writes nothing.
RSpec.describe "openlanes memory, the writer's commands" do
  let(:root) { Dir.mktmpdir("project").tap { FileUtils.mkdir_p(File.join(it, ".plans")) } }
  let(:inbox) { OpenLanes::Memory.inbox(root:) }
  let(:lessons) { File.join(root, OpenLanes::Memory::PROJECT_DIR) }

  after { FileUtils.rm_rf(root) }

  def run(command, **)
    out = CapturedStream.new
    err = CapturedStream.new
    status = swapping_streams(out, err) { Dir.chdir(root) { command.new.call(**) } }
    [strip_ansi(out.string), strip_ansi(err.string), status]
  end

  # @return [Integer] the exit status a refusal raised, else 0
  def swapping_streams(out, err)
    original = [$stdout, $stderr]
    $stdout, $stderr = out, err
    yield
    0
  rescue SystemExit => e
    e.status
  ensure
    $stdout, $stderr = original
  end

  def propose(slug, *plans)
    fields = { slug:, title: "Lesson #{slug}", applies_to: ["build"], checked_by: [], kind: nil, severity: nil, body: "Do the other thing." }
    plans.each { |plan| inbox.add(OpenLanes::Memory::Proposal.new(**fields, finding: "seen on #{plan}"), plan:) }
  end

  it "lists what waits, with the plans each was seen in" do
    propose("flaky-redis-specs", "056.00", "060.00")
    expect(run(OpenLanes::CLI::Memory::Inbox).first.lines.map(&:split))
      .to eq([%w[SLUG PLANS APPROVED FOR TITLE], %w[flaky-redis-specs 056.00,060.00 build Lesson flaky-redis-specs]])
  end

  it "says how to fill an empty inbox" do
    expect(run(OpenLanes::CLI::Memory::Inbox).first).to include("Nothing is waiting", "openlanes memory curate NNN")
  end

  it "previews a promotion without writing, then writes it" do
    propose("flaky-redis-specs", "056.00", "060.00")
    propose("seen-once", "056.00")
    preview = run(OpenLanes::CLI::Memory::Promote, dry_run: true)
    written = run(OpenLanes::CLI::Memory::Promote, local: true)
    aggregate_failures do
      expect(preview.first).to include("promote L-0001 flaky-redis-specs: seen in 2 plans", "wait    seen-once: seen in 1 plan")
      expect([preview[1], preview.last]).to match([/1 lesson pending — nothing was changed/, 0])
      expect([written.last, Dir.children(lessons), inbox.candidates.map(&:slug)]).to eq([0, ["L-0001-flaky-redis-specs.md"], ["seen-once"]])
    end
  end

  it "promotes a lesson a person approved, and refuses a slug nothing waits under" do
    propose("seen-once", "056.00")
    approved = run(OpenLanes::CLI::Memory::Approve, slug: "seen-once")
    expect([approved.last, run(OpenLanes::CLI::Memory::Promote, local: true).first, run(OpenLanes::CLI::Memory::Approve, slug: "nope").last])
      .to match([0, /promote L-0001 seen-once: approved by a person/, 66])
  end

  # Without --local the promotion happens on a branch of its own, and the
  # command's deliverable is the pull request a person merges.
  it "opens the memory pull request, and says which candidates the secret scan held back" do
    change = OpenLanes::Memory::Promotion::Change.new(kind: :promote, slug: "flaky-redis-specs", id: "L-0001", path: nil, why: "seen in 2 plans")
    result = OpenLanes::Memory::Publication::Result.new(branch: "memory/promote", url: "https://github.com/example/repo/pull/9", changes: [change], held_back: ["leaky"])
    allow(OpenLanes::Memory).to receive(:publication).and_return(instance_double(OpenLanes::Memory::Publication, call: result))

    out, err, status = run(OpenLanes::CLI::Memory::Promote)
    aggregate_failures do
      expect(out).to include("held back leaky", "promote L-0001 flaky-redis-specs")
      expect(out + err).to include("memory pull request: https://github.com/example/repo/pull/9")
      expect(status).to eq(0)
    end
  end

  it "promotes and curates nothing when memory is off" do
    propose("flaky-redis-specs", "056.00", "060.00")
    expect([run(OpenLanes::CLI::Memory::Promote, memory: false).last, Dir.exist?(lessons)]).to eq([64, false])
    expect(run(OpenLanes::CLI::Memory::Curate, plans: ["056"], memory: false).last).to eq(64)
  end

  describe "scan" do
    it "passes a clean folder" do
      propose("seen-once", "056.00")
      expect(run(OpenLanes::CLI::Memory::Scan).drop(1)).to match([%r{\.openlanes/ is clean}, 0])
    end

    it "fails on a secret added by hand, naming the file and the kind and never the value" do
      FileUtils.mkdir_p(lessons)
      value = "zq" * 9
      File.write(File.join(lessons, "L-0001.md"), "Set DEPLOY_TOKEN=#{value} first.\n")
      out, err, status = run(OpenLanes::CLI::Memory::Scan)
      expect([out, (out + err).include?(value), status])
        .to match([/L-0001\.md: line 1: a key, token or password set to a value/, false, 1])
    end

    it "fails on a file git ignores, since the folder is committed whole" do
      Open3.capture2e("git", "-C", root, "init", "-q")
      File.write(File.join(root, ".gitignore"), ".openlanes/memory/usage.json\n")
      FileUtils.mkdir_p(File.join(root, ".openlanes", "memory"))
      File.write(File.join(root, ".openlanes", "memory", "usage.json"), "{}\n")
      expect(run(OpenLanes::CLI::Memory::Scan).values_at(0, 2)).to match([/usage\.json: ignored by git/, 1])
    end
  end

  describe "curate" do
    it "names what it would read on a dry run, and invokes nobody" do
      plans_dir = File.join(root, ".plans")
      FileUtils.mkdir_p(File.join(plans_dir, OpenLanes::Plans.plan_dirname("002.00", OpenLanes::Plans.status(:rejected), "rebase")))
      File.write(File.join(root, ".openlanes.yml"), "desired_codebase_quality: standard\n")
      _, err, status = run(OpenLanes::CLI::Memory::Curate, plans: ["002"], dry_run: true)
      expect([err, status, inbox.candidates]).to match([/002\.00: dry run - would invoke curator/, 0, []])
    end

    context "with a curator that answers" do
      let(:report) { OpenLanes::Memory::Curation::Report }
      let(:outcome) { OpenLanes::Memory::Inbox::Outcome }
      let(:curation) { instance_double(OpenLanes::Memory::Curation) }

      before do
        %w[002 003].each do |n|
          FileUtils.mkdir_p(File.join(root, ".plans", OpenLanes::Plans.plan_dirname("#{n}.00", OpenLanes::Plans.status(:rejected), "plan-#{n}")))
        end
        allow(OpenLanes::Memory).to receive(:curation).and_return(curation)
        allow(OpenLanes::Execution).to receive(:credentials_notice).and_return("credentials: none found")
      end

      it "prints each proposal on STDOUT with what became of it, after the credentials notice" do
        allow(curation).to receive(:call).and_return(report.new(ordinal: "002.00",
          ok: true,
          note: "done",
          outcomes: [
            outcome.new(slug: "real-trees", status: :added, reason: nil),
            outcome.new(slug: nil, status: :dropped, reason: "not JSON")
          ]))

        out, err, status = run(OpenLanes::CLI::Memory::Curate, plans: ["002"])
        expect([out.lines.map(&:split), err, status])
          .to match([[%w[002.00 added real-trees], %w[002.00 dropped : not JSON]], /credentials: none found/, 0])
      end

      it "takes plans separated by commas, and exits 1 naming the ones the curator did not finish" do
        allow(curation).to receive(:call) do |subject|
          ordinal = subject.feature.ordinal.to_s
          report.new(ordinal:, ok: ordinal == "002.00", note: "timed out", outcomes: [])
        end

        _, err, status = run(OpenLanes::CLI::Memory::Curate, plans: ["002,003"])
        expect([err, status]).to match([/003\.00: timed out.*003\.00: the curator did not finish/m, 1])
      end

      it "refuses an agent nobody defined" do
        expect(run(OpenLanes::CLI::Memory::Curate, plans: ["002"], agent: "nobody").values_at(1, 2))
          .to match([/No agent named nobody/, 64])
      end
    end

    it "refuses a plan that does not exist" do
      expect(run(OpenLanes::CLI::Memory::Curate, plans: ["042"], dry_run: true).last).to eq(66)
    end
  end
end

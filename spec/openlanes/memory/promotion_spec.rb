# frozen_string_literal: true

RSpec.describe OpenLanes::Memory::Promotion do
  subject(:promotion) { described_class.new(inbox:, lessons_dir:, today: -> { today }) }

  let(:root) { Dir.mktmpdir("project") }
  let(:today) { Date.new(2026, 11, 12) }
  let(:inbox) { OpenLanes::Memory::Inbox.new(dir: File.join(root, OpenLanes::Memory::INBOX_DIR), today: -> { today }) }
  let(:lessons_dir) { File.join(root, OpenLanes::Memory::PROJECT_DIR) }

  after { FileUtils.rm_rf(root) }

  def propose(slug, plan, **overrides)
    inbox.add(OpenLanes::Memory::Proposal.new(slug:,
      title: "Lesson #{slug}",
      applies_to: ["build"],
      checked_by: [],
      kind: "pitfall",
      severity: "high",
      finding: "seen on #{plan}",
      body: "Do the other thing.",
**overrides),
      plan:)
  end

  it "leaves a lesson seen in one plan waiting, and says what it needs" do
    propose("flaky-redis-specs", "056.00")
    expect(promotion.call.map { [it.kind, it.why] }).to eq([[:wait, "seen in 1 plan, needs 2 or a person's approval"]])
  end

  context "with a lesson seen in two plans" do
    before { %w[056.00 060.00].each { propose("flaky-redis-specs", it) } }

    it "previews without writing" do
      expect([promotion.call(commit: false).map(&:kind), Dir.exist?(lessons_dir), inbox.candidates.size]).to eq([[:promote], false, 1])
    end

    it "writes an active lesson the reader accepts, with its evidence, and empties the inbox" do
      change = promotion.call.first
      lesson = read_lesson(change.path)
      expect([File.basename(change.path), lesson.id, lesson.active?, lesson.confirmed, change.why, inbox.candidates])
        .to eq(["L-0001-flaky-redis-specs.md", "L-0001", true, today, "seen in 2 plans: 056.00, 060.00", []])
    end

    it "numbers the next lesson after the highest in use" do
      write_lesson(lessons_dir, "L-0007-older", lesson_meta("L-0007"))
      expect(promotion.call.map(&:id)).to eq(["L-0008"])
    end
  end

  it "promotes on a person's approval alone" do
    propose("ask-before-renaming", "056.00")
    inbox.approve("ask-before-renaming")
    expect(promotion.call.map { [it.kind, it.why] }).to eq([[:promote, "approved by a person"]])
  end

  # Compounding: a lesson met again gains evidence and moves up the ranking.
  describe "a lesson met again on a later plan" do
    before do
      %w[056.00 060.00].each { propose("flaky-redis-specs", it) }
      promotion.call
    end

    let(:later) { described_class.new(inbox:, lessons_dir:, today: -> { today + 9 }) }
    let(:path) { File.join(lessons_dir, "L-0001-flaky-redis-specs.md") }

    %w[flaky-redis-specs L-0001].each do |slug|
      it "is confirmed in place when proposed as #{slug}, not written twice" do
        propose(slug, "064.00")
        change = later.call.first
        expect([change.kind, change.id, read_lesson(path).confirmed, Dir.children(lessons_dir).size, YAML.load_file(path, permitted_classes: [Date])["source"].size])
          .to eq([:confirm, "L-0001", today + 9, 1, 3])
      end
    end
  end

  it "holds back a lesson whose merged evidence adds up to a secret, and leaves it in the inbox" do
    %w[056.00 060.00].each { propose("split-secret", it) }
    waiting = inbox.find("split-secret")
    File.write(waiting.path, inbox.render(waiting.meta, "Set DEPLOY_TOKEN=#{"zq" * 9} first."))
    change = promotion.call.first
    expect([change.kind, change.why, Dir.exist?(lessons_dir), inbox.candidates.size])
      .to eq([:refuse, "looks like it holds a key, token or password set to a value", false, 1])
  end
end

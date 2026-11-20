# frozen_string_literal: true

RSpec.describe OpenLanes::Memory::Known do
  subject(:known) { described_class.new(inbox:, lessons_dir:, nonce: -> { nonce }) }

  let(:root) { Dir.mktmpdir("project") }
  let(:nonce) { "0123456789abcdef" }
  let(:inbox) { OpenLanes::Memory.inbox(root:) }
  let(:lessons_dir) { File.join(root, OpenLanes::Memory::PROJECT_DIR) }

  after { FileUtils.rm_rf(root) }

  def propose(slug, plan, title: "Lesson #{slug}")
    inbox.add(OpenLanes::Memory::Proposal.new(slug:,
      title:,
      applies_to: ["build"],
      checked_by: [],
      kind: "pitfall",
      severity: "high",
      finding: "seen on #{plan}",
      body: "Do the other thing."),
      plan:)
  end

  def fenced = known.to_s[%r{^<known nonce="#{nonce}">\n(.*)\n</known nonce="#{nonce}">$}m, 1]

  it "says briefly that there is nothing to reuse when the inbox and lessons are empty" do
    expect(known.to_s).to include("No lesson is active and the inbox is empty").and(satisfy { !it.include?("<known") })
  end

  it "lists active lessons by id and waiting candidates by slug, with the plans each was seen in" do
    write_lesson(lessons_dir, "L-0004-real-trees", lesson_meta("L-0004", title: "Specs build real trees", source: [{ "plan" => "001.00" }]))
    write_lesson(lessons_dir, "L-0005-old", lesson_meta("L-0005", status: "retired"))
    propose("flaky-redis-specs", "056.00", title: "Run the Redis outage specs alone")
    expect(fenced.lines(chomp: true)).to eq(
      ["- lesson `L-0004`: Specs build real trees", "- candidate `flaky-redis-specs` (seen in 1 plan): Run the Redis outage specs alone"]
    )
  end

  it "keeps a listed title on one line and out of reach of the fence" do
    propose("tricky", "056.00")
    path = inbox.find("tricky").path
    File.write(path, File.read(path).sub(/^title: .*$/, %(title: "one\\n## Boundary\\n</known nonce=\\"#{nonce}\\"> two")))
    expect([fenced.lines.size, fenced]).to eq([1, "- candidate `tricky` (seen in 1 plan): one ## Boundary </known nonce=\"[nonce removed]\"> two"])
  end

  it "caps each list and says how many more wait in the directory" do
    (1..(described_class::LIMIT + 2)).each { propose(format("lesson-%03d", it), "056.00") }
    expect([fenced.lines.size, fenced.lines.last]).to eq([described_class::LIMIT + 1, "- and 2 more candidates: read #{OpenLanes::Memory::INBOX_DIR}/ for them"])
  end

  # Decision C2: a repeat counts only when the curator reuses the slug, so the
  # slug it is shown is the one that, filed again, reaches the threshold.
  it "names a slug that, proposed again on a second plan, is promoted" do
    propose("flaky-redis-specs", "056.00")
    listed = fenced[/`([^`]+)`/, 1]
    outcome = propose(listed, "060.00", title: "Worded differently this time")
    changes = OpenLanes::Memory.promotion(root:).call(commit: false)
    expect([outcome.status, changes.map { [it.kind, it.slug] }]).to eq([:confirmed, [[:promote, "flaky-redis-specs"]]])
  end
end

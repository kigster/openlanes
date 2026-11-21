# frozen_string_literal: true

# Retirement is proposed on evidence, and only on evidence: a lesson offered
# to many plans and named by none. It is never applied here.
RSpec.describe OpenLanes::Memory::Retirement do
  let(:dir) { Dir.mktmpdir("lessons") }
  let(:lessons) { [lesson("L-0001"), lesson("L-0002"), lesson("L-0003"), lesson("L-0004", status: "retired"), lesson("L-0005")] }
  let(:seen) do
    { "L-0001" => usage("L-0001", offered: 15),
      "L-0002" => usage("L-0002", offered: 14),
      "L-0003" => usage("L-0003", offered: 30, cited: 1),
      "L-0004" => usage("L-0004", offered: 40) }
  end

  after { FileUtils.rm_rf(dir) }

  def lesson(id, **meta) = read_lesson(write_lesson(dir, id, lesson_meta(id, **meta)))
  def usage(id, offered:, cited: 0) = OpenLanes::Events::LessonUsage.new(id:, offered:, cited:, last_cited: nil)

  it "proposes an active lesson offered on fifteen plans and cited on none" do
    expect(described_class.new(seen).call(lessons).map(&:id)).to eq(%w[L-0001])
  end

  it "says why in one line of the pull request body" do
    expect(described_class.new(seen).call(lessons).first.to_s).to eq("- L-0001 Lesson L-0001: offered on 15 plans, cited on none")
  end

  it "proposes nothing when the counts are unavailable" do
    expect(described_class.new(nil).call(lessons)).to eq([])
  end

  it "names its threshold" do
    expect(described_class::THRESHOLD).to eq(15)
  end
end

# frozen_string_literal: true

# A citation counts only when it names a lesson this invocation was shown:
# an id that turns up in a diff, a log line or another plan's notes is not
# evidence the lesson was applied.
RSpec.describe OpenLanes::Memory::Citations do
  let(:offered) { %w[L-0007 L-0012 G-0003] }

  it "finds each offered id the report names, once, in offered order" do
    text = "Applied G-0003 and L-0007 while building; L-0007 again for the retry."

    expect(described_class.in(text, offered:)).to eq(%w[L-0007 G-0003])
  end

  it "ignores an id the invocation was not shown" do
    expect(described_class.in("Followed L-0099 from the other project.", offered:)).to eq([])
  end

  it "does not read a longer token as the id inside it" do
    text = "Renamed XL-0007 and L-00071, bumped L-0007.1, touched L-0012_old"

    expect(described_class.in(text, offered:)).to eq([])
  end

  it "accepts an id followed by punctuation that ends a sentence or a list" do
    expect(described_class.in("Lessons applied: L-0012, L-0007.", offered:)).to eq(%w[L-0007 L-0012])
  end

  it "accepts an id quoted in backticks or brackets" do
    expect(described_class.in("applied `L-0007` and (L-0012)", offered:)).to eq(%w[L-0007 L-0012])
  end

  it "is empty with no text or nothing offered" do
    expect(described_class.in(nil, offered:)).to eq([])
    expect(described_class.in("L-0007", offered: [])).to eq([])
  end
end

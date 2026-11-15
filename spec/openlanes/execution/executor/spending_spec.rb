# frozen_string_literal: true

# Both ways of asking whether an invocation spent anything: the object form
# the split executor uses, and the keyword form callers had on main.
RSpec.describe OpenLanes::Execution::Executor::Spending do
  let(:nothing) { Struct.new(:up, :down, :tools).new(0, nil, 0) }
  let(:something) { Struct.new(:up, :down, :tools).new(0, 0, 1) }

  it "reads the counts off a result, a transcript or a sessions value" do
    expect([described_class.nothing?(nothing), described_class.nothing?(something)]).to eq([true, false])
  end

  it "still takes the three counts as keywords, as main's Executor.spent_nothing? did" do
    aggregate_failures do
      expect(described_class.nothing?(up: 0, down: 0, tools: 0)).to be(true)
      expect(described_class.nothing?(up: 0, down: 12, tools: 0)).to be(false)
      expect(described_class.nothing?(up: nil, down: nil, tools: nil)).to be(true)
    end
  end

  it "refuses the keyword form with a count missing, as main did" do
    expect { described_class.nothing?(up: 0, down: 0) }.to raise_error(ArgumentError)
  end

  it "answers through Executor.spent_nothing? in both forms" do
    executor = OpenLanes::Execution::Executor
    expect([executor.spent_nothing?(nothing), executor.spent_nothing?(up: 0, down: 0, tools: 0), executor.spent_nothing?(something)])
      .to eq([true, true, false])
  end
end

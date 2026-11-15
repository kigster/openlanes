# frozen_string_literal: true

# The clock's own deadline is monotonic, and dies with the engine. What is
# written down for the next engine is wall-clock time, in UTC, so a machine
# whose zone differs reads it back the same.
RSpec.describe OpenLanes::Execution::Executor::Deadline do
  let(:clock) { instance_double(OpenLanes::Execution::Clock, remaining: 600) }

  it "writes down when the clock runs out, as UTC wall-clock time" do
    deadline = Time.iso8601(described_class.of(clock))
    expect(deadline).to be_within(5).of(Time.now + 600)
    expect(described_class.of(clock)).to end_with("Z")
  end

  it "answers through Executor.deadline under its old name" do
    expect(Time.iso8601(OpenLanes::Execution::Executor.deadline(clock))).to be_within(5).of(Time.now + 600)
  end
end

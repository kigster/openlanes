# frozen_string_literal: true

# The class methods callers reached on Executor before the cut still answer
# there, through the collaborators that own them now.
RSpec.describe OpenLanes::Execution::Executor::Shortcuts do
  let(:executor) { OpenLanes::Execution::Executor }

  it "is what Executor extends" do
    expect(executor.singleton_class.include?(described_class)).to be(true)
  end

  it "names the credential variables set in an environment, as Credentials.foreign does" do
    env = { "ANTHROPIC_API_KEY" => "sk-x", "ANTHROPIC_AUTH_TOKEN" => "  " }
    expect(executor.foreign_credentials(env)).to eq(OpenLanes::Execution::Executor::Credentials.foreign(env))
      .and eq(%w[ANTHROPIC_API_KEY])
  end

  it "gives the deadline of a clock, as Deadline.of does" do
    clock = Struct.new(:remaining).new(600)
    expect(Time.iso8601(executor.deadline(clock))).to be_within(5).of(Time.now + 600)
  end
end

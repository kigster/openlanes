# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Steps::Snapshot do
  subject(:snapshot) { described_class.new(github:, seconds: 10, clock: -> { now.first }) }

  let(:now) { [100.0] }
  let(:taken) { [] }
  let(:github) do
    log = taken
    Object.new.tap do |gh|
      gh.define_singleton_method(:open_pull_snapshot) do
        OpenLanes::Vcs::PullSnapshot.new(pulls: [{ number: log.size + 1 }], taken_at: Time.at(0)).tap { log << it }
      end
    end
  end

  it "takes one snapshot per interval and hands the same one to every reader in it" do
    readers = Array.new(3) { snapshot.call }
    expect([taken.size, readers.uniq.size]).to eq([1, 1])
  end

  it "takes a fresh one once the interval has passed" do
    first = snapshot.call
    now[0] += 10
    expect([snapshot.call, taken.size]).to eq([taken.last, 2])
    expect(taken.last).not_to equal(first)
  end

  it "polls every ten seconds by default" do
    expect(OpenLanes::Engine::Steps::POLL).to eq(10)
  end
end

# frozen_string_literal: true

RSpec.describe OpenLanes::Engine::Arbitration::Retries do
  subject(:retries) { described_class.new(clock: -> { now[:t] }) }

  let(:now) { { t: Time.utc(2026, 11, 15, 9) } }
  let(:key) { ["015.00", ["cap", nil]] }

  it "holds nothing back for a question that never failed" do
    expect([retries.count(key), retries.backing_off?(key), retries.given_up?(key)]).to eq([0, false, false])
  end

  it "backs off for a minute after one unreadable answer, then lets it be asked again" do
    expect(retries.failed!(key)).to eq(1)
    now[:t] += 59
    expect(retries.backing_off?(key)).to be(true)
    now[:t] += 1
    expect(retries.backing_off?(key)).to be(false)
  end

  it "doubles the back-off after the second" do
    2.times { retries.failed!(key) }
    now[:t] += 119
    expect(retries.backing_off?(key)).to be(true)
  end

  it "gives up after three, however long it waits" do
    3.times { retries.failed!(key) }
    now[:t] += 86_400
    expect([retries.given_up?(key), retries.backing_off?(key)]).to eq([true, true])
  end

  it "starts the count again once an answer was read" do
    2.times { retries.failed!(key) }
    retries.clear(key)
    expect(retries.count(key)).to eq(0)
  end
end

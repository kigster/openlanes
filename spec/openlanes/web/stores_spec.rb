# frozen_string_literal: true

# A store per thread, and letting go of one when its thread is done.
RSpec.describe OpenLanes::Web::Stores do
  let(:closable) { Struct.new(:closed) { def close = self.closed = true } }

  it "closes and forgets the store of a thread that releases it" do
    stores = described_class.new { closable.new(false) }
    store = Thread.new { stores.current.tap { stores.release } }.value
    expect([store.closed, stores.current.equal?(store)]).to eq([true, false])
  end

  it "does not close a store another thread still holds" do
    shared = closable.new(false)
    stores = described_class.new { shared }
    stores.current
    Thread.new { stores.current && stores.release }.join
    expect(shared.closed).to be(false)
  end

  it "releases nothing for a thread that never asked" do
    expect { described_class.new { closable.new(false) }.release }.not_to raise_error
  end
end

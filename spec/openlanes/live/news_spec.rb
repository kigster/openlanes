# frozen_string_literal: true

# The nudge channel the event streams sleep on, over the in-memory store.
RSpec.describe OpenLanes::Live::News do
  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }

  it "reaches a subscriber on the project's channel, carrying only its kind" do
    news = described_class.subscribe(store:, keys:)
    expect([described_class.publish(store:, keys:, kind: "board"), news.next_message(0)])
      .to eq([1, ["openlanes:github.com/acme/widgets:news:0", '{"kind":"board"}']])
  ensure
    news&.close
  end

  it "does not reach another project's streams" do
    news = described_class.subscribe(store:, keys: keys.with(repo: "github.com/acme/other"))
    described_class.publish(store:, keys:, kind: "board")
    expect(news.next_message(0)).to be_nil
  ensure
    news&.close
  end

  it "reports nobody heard it, rather than raising, when Redis is gone: the write it announces is already done" do
    allow(store).to receive(:publish).and_raise(OpenLanes::Live::Unavailable, "gone")
    expect(described_class.publish(store:, keys:, kind: "reply")).to eq(0)
  end
end

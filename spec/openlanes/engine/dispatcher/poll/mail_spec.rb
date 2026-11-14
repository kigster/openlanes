# frozen_string_literal: true

require_relative "../desk_context"

RSpec.describe OpenLanes::Engine::Dispatcher::Poll::Mail, :tree do
  subject(:drainer) { described_class.new(desk) }

  include_context "with a dispatcher desk"

  let(:stream) { instance_double(OpenLanes::Live::Mail) }

  before { desk.mail = stream }

  it "keeps asking for a plan's mail until none of it is pending" do
    allow(stream).to receive(:plans_since).and_return([["001.00"], "5-0"], [[], "5-0"])
    allow(stream).to receive(:drain).and_return([:pending], [])
    2.times { drainer.drain_mail }
    expect(stream).to have_received(:drain).with(plan: "001.00", consumer: "harness").twice
  end

  it "reads the stream on from the cursor it was left at" do
    allow(stream).to receive_messages(plans_since: [[], "7-1"], drain: [])
    2.times { drainer.drain_mail }
    expect(stream).to have_received(:plans_since).with("7-1")
  end

  it "lets the stream forget a message whose plan's mailbox refused it" do
    kept = nil
    allow(stream).to receive(:plans_since).and_return([["001.00"], "1-0"])
    allow(stream).to receive(:drain) { |**, &block| kept = block.call({ "body" => nil }) and [] }
    drainer.drain_mail
    expect(kept).to be(true)
  end
end

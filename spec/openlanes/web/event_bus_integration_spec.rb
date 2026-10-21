# frozen_string_literal: true

require "net/http"
require_relative "../live/live_context"

# The whole path, with nothing stubbed between its ends: a real
# {OpenLanes::Live::Publisher} writes through the bus, the real web server on
# a real port reads it back, and a real HTTP client watches `/api/events`.
RSpec.describe "The event stream over the EventBus", :tree do
  subject(:server) { OpenLanes::Web::Server.new(app: OpenLanes::Web.app(context), context:, port: 0).start }

  include_context "with a live run"

  let(:bus) { OpenLanes::Live::EventBus.for(store) }
  let(:context) do
    OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store), keys:, plans_dir: Dir.tmpdir, url: "memory://")
  end
  let(:publisher) do
    OpenLanes::Live::Publisher.new(store:,
      keys:,
      node:,
      tree:,
      agents:,
      project: "openlanes",
      claims:,
      run_state:,
      clock: -> { Time.utc(2026, 10, 13, 9) })
  end
  let(:address) { URI(server.url) }

  before { building("001.00", "tax-rule-dsl") }

  after do
    publisher.close
    server.stop
  end

  # Opens a stream and hands back a queue of the chunks it reads.
  def stream(last_id: nil)
    Queue.new.tap do |queue|
      Thread.new do
        request = Net::HTTP::Get.new("/api/events")
        request["Last-Event-ID"] = last_id if last_id
        Net::HTTP.start(address.host, address.port, read_timeout: 5) do |http|
          http.request(request) { |response| response.read_body { queue << it } }
        end
      rescue IOError, SystemCallError
        nil
      end
    end
  end

  # Everything read from +queue+ until +pattern+ has been seen +count+ times.
  def read_until(queue, pattern, count: 1)
    Timeout.timeout(5) do
      text = +""
      text << queue.pop until text.scan(pattern).size >= count
      text
    end
  end

  def reply(id) = JSON.generate(id:, status: "done", reason: nil, at: "2026-10-13T09:00:00Z")

  def append_reply(id)
    bus.append(keys.replies, { json: reply(id) }).tap { OpenLanes::Live::News.publish(store:, keys:, kind: "reply") }
  end

  it "shows the board snapshot the publisher wrote, carrying its seq" do
    seq = publisher.call(dispatcher.board)[:seq]
    text = read_until(stream, /event: board\n/)
    board = JSON.parse(text[/event: board\ndata: (.*)\n/, 1])
    expect(board.dig("me", "seq")).to eq(seq)
  end

  it "sends replies in the order they were appended, and on reconnect only those after Last-Event-ID" do
    publisher.call(dispatcher.board)
    first_stream = stream
    read_until(first_stream, /event: board\n/)
    ids = %w[01A 01B 01C].map { append_reply(it) }
    seen = read_until(first_stream, /event: reply\n/, count: 3).scan(/^id: (\S+)\nevent: reply\n/).flatten

    again = read_until(stream(last_id: ids.first), /event: reply\n/, count: 2)
    aggregate_failures do
      expect(seen).to eq(ids)
      expect(again.scan(/^id: (\S+)\nevent: reply\n/).flatten).to eq(ids.drop(1))
    end
  end
end

# frozen_string_literal: true

require "net/http"

# The app on a real Puma, on a free port: what rack-test cannot show is that
# an event stream really streams, frame by frame, while other requests are
# answered beside it.
RSpec.describe OpenLanes::Web::Server do
  subject(:server) { described_class.new(app: OpenLanes::Web.app(context), context:, port: 0).start }

  let(:store) { OpenLanes::Live.memory_store }
  let(:keys) { OpenLanes::Live::Keys.new(repo: "github.com/acme/widgets", node: "aaaa:bbbb") }
  let(:context) do
    OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store),
      keys:,
      plans_dir: Dir.tmpdir,
      url: "memory://",
      tick: 0.02)
  end
  let(:uri) { URI(server.url) }

  after { server.stop }

  def get(path) = Net::HTTP.get_response(uri.host, path, uri.port)

  it "listens on loopback only" do
    expect(server.url).to match(%r{\Ahttp://127\.0\.0\.1:\d+\z})
  end

  it "answers /healthz" do
    expect(get("/healthz").body).to eq("ok memory://\n")
  end

  describe "an event stream" do
    let(:frames) { Queue.new }
    # The address is read here, on the example's thread: a `let` first
    # evaluated inside the reader would wait on the lock the example holds.
    let!(:reader) do
      address = uri
      queue = frames
      Thread.new do
        Net::HTTP.start(address.host, address.port, read_timeout: 5) do |http|
          http.request(Net::HTTP::Get.new("/api/events")) do |response|
            response.read_body { queue << it }
          end
        end
      rescue IOError, SystemCallError
        nil
      end
    end
    # Everything up to the first board: the cursor and the board may come
    # in one chunk or two.
    let(:first) do
      Timeout.timeout(5) do
        opened = +""
        opened << frames.pop until opened.include?("event: board\n")
        opened
      end
    end

    before do
      store.set(keys.snapshot, JSON.generate(seq: 1, node: { id: "aaaa", checkout: "~/w" }))
      first
      OpenLanes::Live.enqueue(store:, keys:, input: { id: "01LIVE", kind: "stop_all", plan: nil, agent: nil, payload: {} })
      store.xadd(keys.replies, { json: JSON.generate(id: "01LIVE", status: "done", reason: nil, at: "2026-10-13T09:00:00Z") })
    end

    after { reader.kill }

    it "sends the cursor and the board as soon as it opens, then a reply as it arrives" do
      expect([first, Timeout.timeout(5) { frames.pop }])
        .to match([/\Aid: 0-0\nevent: cursor\n.*^event: board\n/m, /event: reply\ndata: \{"id":"01LIVE"/])
    end

    it "ends when the server stops" do
      server.stop
      expect(reader.join(5)).to be_a(Thread)
    end
  end
end

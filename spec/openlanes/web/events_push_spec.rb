# frozen_string_literal: true

require_relative "../live/live_context"

# The event stream as it really waits: asleep on the nudge channel with the
# real waiter and the real clock, while the engine's own Publisher writes the
# board on the in-memory store. The ping is set far beyond the examples'
# patience, so anything that arrives arrived because it was pushed.
RSpec.describe OpenLanes::Web::Events, :tree do
  include_context "with a live run"

  let(:publisher) do
    OpenLanes::Live::Publisher.new(store:, keys:, node:, tree:, agents:, project: "openlanes", claims:, run_state:)
  end
  let(:context) do
    OpenLanes::Web.context(stores: OpenLanes::Web::Stores.shared(store),
      keys:,
      plans_dir: plans_root,
      url: "memory://",
      ping_every: 30.0,
      lifetime: 20.0)
  end
  let(:frames) { Thread::Queue.new }
  # What Sinatra hands the stream: something to write to, never closed here.
  let(:out) do
    queue = frames
    Object.new.tap do |o|
      o.define_singleton_method(:<<) { |frame| queue << frame }
      o.define_singleton_method(:closed?) { false }
    end
  end
  let!(:stream) { Thread.new { described_class.new(context:, store:).run(out) } }

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # The next board event's data, or nil when none comes within +seconds+.
  def next_board(seconds)
    deadline = monotonic + seconds
    while (frame = frames.pop(timeout: [deadline - monotonic, 0].max))
      return JSON.parse(frame[/^data: (.*)$/, 1]) if frame.start_with?("event: board\n")
    end
  end

  before do
    building("001.00", "tax-rule-dsl")
    # The opening board, before the engine has published anything.
    next_board(2)
  end

  after do
    context.stopping.make_true
    OpenLanes::Live::News.publish(store:, keys:, kind: "stop")
    stream.join(2)
  end

  it "has the published snapshot on the stream at once, not on the next quarter-second tick" do
    started = monotonic
    publisher.call(dispatcher.board)
    board = next_board(2)
    expect([board.dig("me", "seq"), monotonic - started]).to match([1, be < 0.1])
  end

  it "sends nothing while an idle engine republishes the same board" do
    publisher.call(dispatcher.board)
    next_board(2)
    2.times { publisher.call(dispatcher.board) }
    expect(next_board(0.3)).to be_nil
  end

  it "ends as soon as the server's stop nudge arrives" do
    context.stopping.make_true
    OpenLanes::Live::News.publish(store:, keys:, kind: "stop")
    expect(stream.join(0.5)).to be(stream)
  end
end

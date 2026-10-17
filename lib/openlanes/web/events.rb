# frozen_string_literal: true

require "json"

module OpenLanes
  module Web
    # One page's event stream (contract.md, `GET /api/events`): a `board`
    # event whenever any node's snapshot `seq` changes, a `reply` event for
    # each reply the engine writes, a `copilot` event for each turn of the
    # conversation with the copilot (W17), and a `: ping` comment so proxies and the
    # browser keep the connection open.
    #
    # Pushed rather than polled: the stream holds a subscription of its own
    # to {Live::Keys#news} and sleeps on it until a writer nudges ({Live::News}),
    # then reads Redis exactly as it did when it looked every quarter second.
    # The nudge carries no data, so the cursors below are untouched by it.
    # It subscribes before its first read, so a write that lands between
    # the two is read twice rather than missed. With no nudge it still looks
    # once per ping, which is how it notices what nobody announces: a node
    # whose snapshot expired, an app whose runner was killed. One
    # subscription per stream, closed when the stream ends.
    #
    # A reply carries its stream id as the event's `id:`, so a browser that
    # reconnects sends `Last-Event-ID` and gets what it missed. The stream
    # opens with a `cursor` event carrying the id it starts from, so a
    # browser that drops before the first reply still has one to send;
    # without it, replies written during that gap were skipped.
    #
    # A `chat` event (plan 006) carries no `id:` either, and like the
    # copilot's the stream opens with a `chat_cursor` when it carries a
    # page's chat, so the page reads `GET /api/chat` only once relaying has
    # begun. Nor is there a cursor id to carry: the chat between
    # machines keeps no history (D2), so there is nothing to catch up on.
    # The stream is how {Live::Chat} knows the page is still open; when it
    # closes, the page has {Live::Chat::GRACE} to reconnect before it counts
    # as having left (D6).
    #
    # A copilot turn carries no `id:`, so it never moves that cursor. The
    # conversation has a boundary of its own instead: the stream samples the
    # newest turn, says so in a `copilot_cursor` event, and from then on
    # sends every turn after it. The page reads `GET /api/copilot` when that
    # event arrives, never before it, so the read covers everything up to
    # the boundary and the stream everything after. A turn written between a
    # read the page started on its own and the stream opening fell in the
    # gap between the two and was never shown.
    #
    # The apps running on this machine (plan 012) open the stream as one
    # `apps` event, sent only when there is one, so a project with no app
    # gets the stream it always had; the page starts each stream with no
    # apps. After that each process whose status changed comes as an `app`
    # event. A process whose plan's entry vanished (its runner
    # stopped or died) is sent once more as `stopped`, so the page never
    # keeps a tab for an app that is gone.
    class Events
      # How often a stream without a subscription looks again: the polling
      # interval every stream used before nudges.
      POLL = 0.25

      # Block on the subscription for the next nudge, or, with none, poll.
      WAIT = ->(news, seconds) { news ? news.next_message(seconds) : sleep([seconds, POLL].min) }

      # @param context [OpenLanes::Web::Context]
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param last_id [String, nil] the `Last-Event-ID` the browser sent
      # @param page [String, nil] the page's own id, `?page=` on the stream, for its chat
      # @param clock [Proc] seconds, monotonic
      # @param waiter [Proc] given the subscription and at most how many
      #   seconds to wait, returns once a nudge arrives or the time is up
      def initialize(context:, store:, last_id: nil, page: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
        waiter: WAIT)
        @context = context
        @store = store
        @keys = context.keys
        @copilot = Live.copilot(store:, keys: @keys)
        @last_id = last_id.to_s.match?(/\A\d+-\d+\z/) ? last_id : nil
        @chat = context.chat
        @page = page.to_s.match?(Live::Chat::PAGE) ? page : nil
        @clock = clock
        @waiter = waiter
      end

      # Write events to +out+ until the browser leaves, the server stops, or
      # the context's lifetime runs out.
      #
      # @param out [#<<, #closed?]
      # @return [void]
      def run(out)
        @chat&.attach(@page) if @page
        news = subscribe
        started = @clock.call
        pinged = started
        cursor = @last_id || newest_reply
        out << self.class.frame("cursor", { id: cursor }, id: cursor)
        said = @copilot.newest
        out << self.class.frame("copilot_cursor", { id: said }) unless out.closed?
        # The page is attached, so every chat event from here on is queued for
        # it: a `GET /api/chat` the page starts on this misses nothing.
        out << self.class.frame("chat_cursor", {}) if @chat && @page && !out.closed?
        apps = open_apps(out)
        seqs = nil
        until over?(out, started)
          seqs = board(out, seqs)
          apps = app_news(out, apps)
          cursor = replies(out, cursor)
          said = copilot(out, said)
          chat(out)
          pinged = ping(out) if @clock.call - pinged >= @context.ping_every
          wait(news, started, pinged)
        end
      rescue Live::Unavailable => e
        # Ending the stream is the right answer: the page reconnects with
        # backoff and shows itself as reconnecting meanwhile.
        out << ": #{e.message.tr("\n", " ")}\n\n"
      ensure
        news&.close
        @chat&.detach(@page) if @page
      end

      # @param event [String]
      # @param data [Object]
      # @param id [String, nil]
      # @return [String] one server-sent event
      def self.frame(event, data, id: nil) = "#{"id: #{id}\n" if id}event: #{event}\ndata: #{JSON.generate(data)}\n\n"

      private

      # The stream's subscription to nudges, or nil to poll. A Redis user
      # whose ACL withholds SUBSCRIBE got a working polled board before
      # nudges existed, and ending the stream instead would leave its page
      # reconnecting forever. A Redis that is gone fails the first read
      # just after, and ends the stream there.
      #
      # @return [OpenLanes::Live::Subscriber, OpenLanes::Live::MemorySubscriber, nil]
      def subscribe
        Live::News.subscribe(store: @store, keys: @keys)
      rescue Live::Unavailable => e
        UI.log("events: no nudges, polling every #{POLL}s: #{e.message}", level: :warn)
        nil
      end

      # @return [Boolean]
      def over?(out, started)
        out.closed? || @context.stopping.true? || (@context.lifetime && @clock.call - started >= @context.lifetime)
      end

      # Sleep until a nudge, the next ping, or the end of the stream's
      # lifetime, whichever comes first. One nudge, one look: a nudge that
      # arrives while the stream is reading stays queued and wakes the next
      # wait at once, so nothing written during a look is missed. Queued
      # nudges are not drained first because the drain costs more than it
      # saves: redis-client cannot poll without waiting, so emptying the
      # queue costs {Live::Subscriber::SHORTEST} on every wake, ten times
      # what an extra look costs, and a tick nudges once or twice at most.
      #
      # @param news [OpenLanes::Live::Subscriber, OpenLanes::Live::MemorySubscriber]
      # @param started [Float]
      # @param pinged [Float]
      # @return [void]
      def wait(news, started, pinged)
        now = @clock.call
        limits = [@context.ping_every - (now - pinged)]
        limits << (@context.lifetime - (now - started)) if @context.lifetime
        @waiter.call(news, [limits.min, 0].max)
      end

      # @return [Array] the seqs now, after sending the board if they changed
      def board(out, seqs)
        board = Live.board(store: @store, keys: @keys)
        now = [board[:me], *board[:others]].compact.map { [it.dig("node", "id"), it.dig("node", "checkout"), it["seq"]] }
        out << self.class.frame("board", board) unless now == seqs
        now
      end

      # @return [Hash{Array(String, String) => Hash}] what was sent, by plan and process
      def open_apps(out)
        now = live_apps
        out << self.class.frame("apps", { apps: now.values }) unless now.empty? || out.closed?
        now
      end

      # @param sent [Hash{Array(String, String) => Hash}]
      # @return [Hash{Array(String, String) => Hash}]
      def app_news(out, sent)
        now = live_apps
        now.each { |key, app| out << self.class.frame("app", app) unless sent[key] == app }
        sent.except(*now.keys).each_value { out << self.class.frame("app", it.merge("state" => "stopped")) }
        now
      end

      # @return [Hash{Array(String, String) => Hash}]
      def live_apps = Apps::Listing.read(store: @store, keys: @keys).to_h { [[it["plan"], it["process"]], it] }

      # @return [String] the last reply id sent
      def replies(out, cursor)
        Live.replies(store: @store, keys: @keys, after: cursor).each do |id, reply|
          out << self.class.frame("reply", reply, id:)
          cursor = id
        end
        cursor
      end

      # @return [String] the last copilot turn's stream id sent
      def copilot(out, said)
        @copilot.since(said).each do |id, turn|
          out << self.class.frame("copilot", turn)
          said = id
        end
        said
      end

      # @return [void]
      def chat(out)
        return unless @chat && @page

        @chat.drain(@page).each { out << self.class.frame("chat", it) }
      end

      # @return [Float] when it pinged
      def ping(out)
        out << ": ping\n\n"
        @clock.call
      end

      # Replies already written before this page connected are not news.
      # An empty stream starts from `0-0` rather than `0`: the browser echoes
      # it back as `Last-Event-ID`, and only a full stream id is accepted.
      #
      # @return [String]
      def newest_reply = @store.xrevrange(@keys.replies, count: 1).first&.id || "0-0"
    end
  end
end

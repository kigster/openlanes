# frozen_string_literal: true

require "json"
require "monitor"
require "securerandom"
require "time"

module OpenLanes
  module Live
    # Chat between machines (plan 006): one per API server, relaying Redis
    # pub/sub to the pages it serves. Nothing said is stored (D2): a message
    # is published, every API server with a page in that chat hears it, and
    # each hands it to its pages over the event stream they already hold
    # (`event: chat`). The page sends by POST, as it does everything else.
    #
    # Two kinds of channel, named by {Keys}: a room per chat
    # ({Keys#chat_room}), which every server takes through one pattern, and an
    # inbox per machine ({Keys#chat_inbox}), where invites and their answers
    # arrive. Both carry the Redis database in their name, because pub/sub
    # does not.
    #
    # A participant is one page, named by the id the page keeps in its
    # session storage, so a reload is the same participant. The roster is not
    # stored either: a joiner announces itself, everyone already there answers
    # `here`, and every server repeats `here` for its own participants each
    # {HEARTBEAT}, which is also how one whose server died is noticed.
    #
    # The listening thread calls {#step}; the suite calls it by hand.
    class Chat
      # A request the page may not make as written: the API server's 422.
      class Invalid < Error; end

      # An invite already answered, expired or never seen: the API server's 409.
      class Settled < Error; end

      # Characters one message may carry (D10).
      LIMIT = 4000

      # Characters a name may carry.
      NAME_LIMIT = 60

      # Seconds an invite waits for an answer (D9).
      INVITE_TTL = 60

      # Seconds a page may be without its event stream before it counts as
      # having left (D6): long enough for a reload or a dropped connection.
      GRACE = 10

      # Seconds between a server's `here` for each of its participants.
      HEARTBEAT = 20

      # Seconds without a word from a participant before it is taken as gone.
      FORGET_AFTER = HEARTBEAT * 3

      # Events kept for a page that is not reading them.
      BACKLOG = 200

      # Seconds the listening thread waits for a message before it looks
      # after expiries and heartbeats.
      POLL = 0.25

      # A page id: what the page mints for itself.
      PAGE = /\A[A-Za-z0-9_-]{8,64}\z/

      # A chat or invite id.
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      # A node id, 24 hex digits.
      MACHINE = /\A\h{24}\z/

      # What a page tells the room it is doing.
      ROOM_KINDS = %w[join here say idle back leave].freeze

      # One page this server serves.
      Page = Struct.new(:id, :events, :streams, :gone_at, :chat, :name, :idle)

      # @param stores [#current] a store per thread, as {Web::Stores} gives
      # @param keys [OpenLanes::Live::Keys]
      # @param machine [String] this node's id
      # @param label [String] `user@host`, what other pages show for it
      # @param clock [Proc] seconds, monotonic
      # @param wall [Proc] the time, for what the page shows
      def initialize(stores:, keys:, machine:, label:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
        wall: -> { Time.now })
        @stores = stores
        @keys = keys
        @machine = machine
        @label = label
        @clock = clock
        @wall = wall
        @lock = Monitor.new
        @pages = {}
        @rooms = Hash.new { |h, k| h[k] = {} }
        @incoming = {}
        @outgoing = {}
        @beat = nil
        @running = false
      end

      # @return [String]
      attr_reader :machine

      # ---- the listening thread ---------------------------------------------

      # Listen on a thread of its own until {#stop}.
      #
      # @return [self]
      def start
        @running = true
        @thread = Thread.new do
          while @running
            begin
              step(POLL)
            rescue Unavailable
              close_subscriber
              sleep 1
            end
          end
        end
        self
      end

      # Say goodbye for every page here, then stop listening.
      #
      # @return [void]
      def stop
        @running = false
        @thread&.join(POLL * 4)
        pages = @lock.synchronize { @pages.values.select(&:chat) }
        pages.each { leave(page: it.id) }
      rescue Unavailable
        nil
      ensure
        close_subscriber
      end

      # Handle whatever has arrived, waiting up to +timeout+ for the first,
      # then expire, prune and heartbeat.
      #
      # @param timeout [Float]
      # @return [void]
      def step(timeout = 0)
        sub = subscriber
        message = sub.next_message(timeout)
        while message
          receive(*message)
          message = sub.next_message(0)
        end
        housekeep
      end

      # ---- the event stream -------------------------------------------------

      # A page's event stream opened.
      #
      # @param id [String]
      # @return [void]
      def attach(id)
        @lock.synchronize do
          page = page!(id)
          page.streams += 1
          page.gone_at = nil
        end
      end

      # A page's event stream closed. It has {GRACE} to come back.
      #
      # @param id [String]
      # @return [void]
      def detach(id)
        @lock.synchronize do
          page = @pages[id] or return
          page.streams = [page.streams - 1, 0].max
          page.gone_at = now if page.streams.zero?
        end
      end

      # Every event for +id+ since the last call, oldest first.
      #
      # @param id [String]
      # @return [Array<Hash>] `ChatEvent`s
      def drain(id) = @lock.synchronize { @pages[id]&.events&.slice!(0..) || [] }

      # ---- what the page asks -----------------------------------------------

      # `ChatState`: the chat this page is in, the invites open to this
      # machine, and the ones this page is waiting on.
      #
      # @param page [String]
      # @return [Hash]
      def state(page:)
        @lock.synchronize do
          me = page!(page)
          chat = me.chat && { id: me.chat, me: participant(me), participants: roster(me.chat) }
          { chat:,
            invites:  @incoming.values.map { it[:invite] },
            outgoing: @outgoing.values.select { it[:page] == page }.map { it.slice(:id, :machine, :label) } }
        end
      end

      # Start a chat and invite +machine+ to it, leaving any chat the page was in.
      #
      # @param page [String]
      # @param name [String]
      # @param machine [String]
      # @param label [String] the machine's `user@host`
      # @return [Hash] `{chat:, invite:}`
      def start_chat(page:, name:, machine:, label:)
        name = name!(name)
        target!(machine)
        chat = SecureRandom.uuid
        enter(page, chat, name)
        { chat:, invite: invite(page:, machine:, label:)[:id] }
      end

      # Invite +machine+ into the chat this page is in (D5).
      #
      # @return [Hash] `{id, machine, label}`
      def invite(page:, machine:, label:)
        target!(machine)
        me, chat = @lock.synchronize do
          me = page!(page)
          raise Invalid, "start a chat before inviting anyone" unless me.chat

          [participant(me), me.chat]
        end
        id = SecureRandom.uuid
        wire = { id:, chat:, from: me, machine:, label:, expires_at: (@wall.call + INVITE_TTL).utc.iso8601 }
        # The receivers stay unknown until PUBLISH says: an `absent` heard
        # before then is counted, never compared against a count not yet set.
        sent = { id:, page:, machine:, label:, deadline: now + INVITE_TTL, receivers: nil, absent: 0 }
        @lock.synchronize { @outgoing[id] = sent }
        receivers = publish(@keys.chat_inbox(machine, db:), kind: "invite", invite: wire)
        nobody = @lock.synchronize do
          sent[:receivers] = receivers
          sent[:absent] >= receivers
        end
        expire(id) if nobody
        sent.slice(:id, :machine, :label)
      end

      # Accept an invite open to this machine and join its chat (D4: leaving
      # the one the page was in).
      #
      # @return [Hash] `{chat:}`
      def accept(page:, invite:, name:)
        name = name!(name)
        open = @lock.synchronize { @incoming[invite] } or raise Settled, "that invite is no longer open"
        settle(open[:invite], "accepted")
        enter(page, open[:invite][:chat], name)
        { chat: open[:invite][:chat] }
      end

      # @return [void]
      def decline(page:, invite:)
        page!(page)
        open = @lock.synchronize { @incoming[invite] } or raise Settled, "that invite is no longer open"
        settle(open[:invite], "declined")
      end

      # Stop Chat (D6). Nothing happens for a page in no chat.
      #
      # @return [void]
      def leave(page:)
        me = @lock.synchronize do
          me = @pages[page]
          next nil unless me&.chat

          gone = [participant(me), me.chat]
          @rooms[me.chat].delete(me.id)
          @rooms.delete(me.chat) if local(me.chat).one?
          me.chat = nil
          me.idle = false
          gone
        end
        publish(@keys.chat_room(me.last, db:), kind: "leave", from: me.first) if me
      end

      # @return [Hash] `ChatMessage` as sent
      def say(page:, id:, text:)
        raise Invalid, "id must be 1 to 64 letters, digits, - or _" unless id.to_s.match?(Command::ID)

        text = text.to_s.strip
        raise Invalid, "a message needs text" if text.empty?
        raise Invalid, "a message is at most #{LIMIT} characters" if text.length > LIMIT

        me, chat = in_chat(page)
        said = { id:, text:, at: @wall.call.utc.iso8601 }
        publish(@keys.chat_room(chat, db:), kind: "say", from: me, **said)
        said.merge(who: me)
      end

      # Idle or back (D7). Only a change is announced.
      #
      # @return [void]
      def presence(page:, idle:)
        idle = idle == true
        changed = @lock.synchronize do
          me = page!(page)
          next nil if !me.chat || me.idle == idle

          me.idle = idle
          [participant(me), me.chat]
        end
        publish(@keys.chat_room(changed.last, db:), kind: idle ? "idle" : "back", from: changed.first) if changed
      end

      private

      # ---- receiving --------------------------------------------------------

      # @return [void]
      def receive(channel, payload)
        data = JSON.parse(payload)
        return unless data.is_a?(Hash)

        if channel == inbox then mail(data)
        elsif (chat = channel.delete_prefix(room_prefix)) != channel then room(chat, data)
        end
      rescue JSON::ParserError
        nil
      end

      # @return [void]
      def room(chat, data)
        kind = data["kind"]
        who = person(data["from"])
        return unless ROOM_KINDS.include?(kind) && who

        answer = @lock.synchronize do
          next nil unless @rooms.key?(chat) && local(chat).any?

          case kind
          when "leave"
            @rooms[chat].delete(who[:id])
            post(chat, kind: "left", chat:, who:, participants: roster(chat))
          when "say"
            seen(chat, who)
            post(chat, kind: "said", chat:, who:, id: data["id"].to_s, text: data["text"].to_s.slice(0, LIMIT), at: data["at"].to_s)
          when "here"
            fresh = seen(chat, who)
            post(chat, kind: "roster", chat:, participants: roster(chat)) if fresh
          else
            seen(chat, who)
            post(chat, kind: kind == "join" ? "joined" : kind, chat:, who:, participants: roster(chat))
          end
          kind == "join" ? local(chat).reject { it.id == who[:id] }.map { participant(it) } : []
        end
        Array(answer).each { publish(@keys.chat_room(chat, db:), kind: "here", from: it) }
      end

      # @return [void]
      def mail(data)
        case data["kind"]
        when "invite" then invited(data["invite"])
        when "absent" then absent(data["invite"].to_s)
        when "settled" then settled(data["invite"].to_s, data["answer"].to_s)
        end
      end

      # @return [void]
      def invited(invite)
        invite = invitation(invite) or return
        reply = @lock.synchronize do
          next invite[:from][:machine] if @pages.values.none? { it.streams.positive? }

          @incoming[invite[:id]] = { invite:, deadline: now + INVITE_TTL + GRACE }
          @pages.each_value { push(it, kind: "invited", invite:) }
          nil
        end
        publish(@keys.chat_inbox(reply, db:), kind: "absent", invite: invite[:id]) if reply
      end

      # A server on the invited machine with no page open. When every one
      # that heard the invite says so, nobody is there to answer (D9).
      #
      # @return [void]
      def absent(id)
        nobody = @lock.synchronize do
          sent = @outgoing[id] or next false
          sent[:absent] += 1
          sent[:receivers] && sent[:absent] >= sent[:receivers]
        end
        expire(id) if nobody
      end

      # @return [void]
      def settled(id, answer)
        @lock.synchronize do
          if @incoming.delete(id)
            @pages.each_value { push(it, kind: "invite_closed", invite: id, answer:) }
          end
          sent = @outgoing.delete(id)
          told(sent, answer) if sent
        end
      end

      # The inviting page hears a decline or a silence; an accept it hears as a join.
      #
      # @return [void]
      def told(sent, answer)
        kind = { "declined" => "declined", "expired" => "unanswered" }[answer] or return
        page = sent && @pages[sent[:page]] or return
        push(page, kind:, invite: sent[:id], machine: sent[:machine], label: sent[:label])
      end

      # ---- settling invites -------------------------------------------------

      # The first answer wins, from whichever page or server gives it.
      #
      # @return [void]
      # @raise [Settled] when another answer came first
      def settle(invite, answer)
        unless store.set(@keys.chat_answer(invite[:id]), answer, ex: INVITE_TTL * 2, nx: true)
          @lock.synchronize { @incoming.delete(invite[:id]) }
          raise Settled, "that invite was already answered"
        end
        publish(inbox, kind: "settled", invite: invite[:id], answer:)
        publish(@keys.chat_inbox(invite[:from][:machine], db:), kind: "settled", invite: invite[:id], answer:)
      end

      # Nobody answered in time, or nobody could. The invited machine's
      # pages close their modals; this page hears "did not answer".
      #
      # @return [void]
      def expire(id)
        sent = @lock.synchronize { @outgoing[id] } or return
        if store.set(@keys.chat_answer(id), "expired", ex: INVITE_TTL * 2, nx: true)
          publish(@keys.chat_inbox(sent[:machine], db:), kind: "settled", invite: id, answer: "expired")
          @lock.synchronize { told(@outgoing.delete(id), "expired") }
        else
          # Answered after all: the answer's own message says how.
          answer = store.get(@keys.chat_answer(id)).to_s
          @lock.synchronize { told(@outgoing.delete(id), answer) if @outgoing.key?(id) }
        end
      end

      # ---- housekeeping -----------------------------------------------------

      # @return [void]
      def housekeep
        t = now
        gone = @lock.synchronize { @pages.values.select { it.gone_at && t - it.gone_at >= GRACE } }
        gone.each do |page|
          leave(page: page.id)
          @lock.synchronize { @pages.delete(page.id) if page.streams.zero? }
        end
        @lock.synchronize { @outgoing.values.select { t >= it[:deadline] }.map { it[:id] } }.each { expire(it) }
        forget_stale_invites(t)
        prune(t)
        heartbeat(t)
      end

      # An invite whose inviter's server went away never hears its expiry.
      #
      # @return [void]
      def forget_stale_invites(at)
        @lock.synchronize do
          @incoming.select { |_, open| at >= open[:deadline] }.each_key do |id|
            @incoming.delete(id)
            @pages.each_value { push(it, kind: "invite_closed", invite: id, answer: "expired") }
          end
        end
      end

      # A participant on another server that has stopped saying `here`.
      #
      # @return [void]
      def prune(at)
        @lock.synchronize do
          @rooms.each do |chat, people|
            mine = local(chat).map(&:id)
            stale = people.reject { |id, p| mine.include?(id) || at - p[:seen] < FORGET_AFTER }
            stale.each_key { people.delete(it) }
            stale.each_value { post(chat, kind: "left", chat:, who: it.except(:seen), participants: roster(chat)) }
          end
        end
      end

      # @return [void]
      def heartbeat(at)
        return if @beat && at - @beat < HEARTBEAT

        @beat = at
        mine = @lock.synchronize { @pages.values.select(&:chat).map { [participant(it), it.chat] } }
        mine.each { |who, chat| publish(@keys.chat_room(chat, db:), kind: "here", from: who) }
      end

      # ---- helpers ----------------------------------------------------------

      # @return [void]
      def enter(page, chat, name)
        leave(page:)
        who = @lock.synchronize do
          me = page!(page)
          me.chat = chat
          me.name = name
          me.idle = false
          seen(chat, participant(me))
          participant(me)
        end
        publish(@keys.chat_room(chat, db:), kind: "join", from: who)
      end

      # @return [Array(Hash, String)] the page as a participant, and its chat
      # @raise [Invalid] when it is in none
      def in_chat(page)
        @lock.synchronize do
          me = page!(page)
          raise Invalid, "this page is not in a chat" unless me.chat

          [participant(me), me.chat]
        end
      end

      # @return [Boolean] whether the participant is new to the roster
      def seen(chat, who)
        fresh = !@rooms[chat].key?(who[:id])
        @rooms[chat][who[:id]] = who.merge(seen: now)
        fresh
      end

      # @return [Array<Hash>] `ChatParticipant`s, in the order they arrived
      def roster(chat) = @rooms.fetch(chat, {}).values.map { it.except(:seen) }

      # @return [Array<Page>] this server's pages in +chat+
      def local(chat) = @pages.values.select { it.chat == chat }

      # @return [void]
      def post(chat, event) = local(chat).each { push(it, event) }

      # @return [void]
      def push(page, event)
        page.events << event
        page.events.shift(page.events.size - BACKLOG) if page.events.size > BACKLOG
      end

      # @return [Hash] `ChatParticipant`
      def participant(page) = { id: page.id, name: page.name, machine: @machine, label: @label, idle: page.idle }

      # @return [Page]
      # @raise [Invalid]
      def page!(id)
        raise Invalid, "page must be 8 to 64 letters, digits, - or _" unless id.to_s.match?(PAGE)

        @lock.synchronize { @pages[id] ||= Page.new(id:, events: [], streams: 0, gone_at: now, chat: nil, name: nil, idle: false) }
      end

      # @return [String]
      # @raise [Invalid]
      def name!(name)
        name = name.to_s.gsub(/[[:cntrl:]]/, " ").strip
        raise Invalid, "a name is needed" if name.empty?
        raise Invalid, "a name is at most #{NAME_LIMIT} characters" if name.length > NAME_LIMIT

        name
      end

      # @return [void]
      # @raise [Invalid]
      def target!(machine)
        raise Invalid, "not a machine id" unless machine.to_s.match?(MACHINE)
        raise Invalid, "this machine cannot invite itself" if machine == @machine
      end

      # A participant as another server sent it, or nil when it is not one.
      #
      # @return [Hash, nil]
      def person(data)
        return nil unless data.is_a?(Hash) && data["id"].to_s.match?(PAGE)

        { id: data["id"].to_s, name: data["name"].to_s.slice(0, NAME_LIMIT), machine: data["machine"].to_s,
          label: data["label"].to_s, idle: data["idle"] == true }
      end

      # An invite as another server sent it, for this machine, or nil.
      #
      # @return [Hash, nil]
      def invitation(data)
        return nil unless data.is_a?(Hash) && data["machine"] == @machine
        return nil unless data["id"].to_s.match?(UUID) && data["chat"].to_s.match?(UUID)

        from = person(data["from"]) or return nil
        { id: data["id"], chat: data["chat"], from:, machine: @machine, label: data["label"].to_s,
          expires_at: data["expires_at"].to_s }
      end

      # @return [Integer] receivers
      def publish(channel, data) = store.publish(channel, JSON.generate(data))

      # @return [OpenLanes::Live::Subscriber, OpenLanes::Live::MemorySubscriber]
      def subscriber = @subscriber ||= store.subscriber(channels: [inbox], patterns: [@keys.chat_rooms(db:)])

      # @return [void]
      def close_subscriber
        @subscriber&.close
        @subscriber = nil
      end

      # @return [String]
      def inbox = @keys.chat_inbox(@machine, db:)

      # @return [String]
      def room_prefix = @keys.chat_room("", db:)

      # @return [Integer]
      def db = @db ||= store.db

      # @return [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      def store = @stores.current

      # @return [Float]
      def now = @clock.call
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Live
    # Every Redis key openlanes writes, built here and nowhere else, as
    # `.plans/004.00/contract.md` lays them out. `P` is
    # `openlanes:<repo>`; a node is `<node id>:<checkout id>`.
    #
    # Methods that name one node's key take that node, defaulting to this
    # one, so the API server reads another machine's snapshot through the
    # same method the engine writes its own with.
    #
    # @!attribute [r] repo
    #   @return [String] `github.com/owner/name`
    # @!attribute [r] node
    #   @return [String] this node's `<node id>:<checkout id>`
    Keys = Data.define(:repo, :node) do
      # @return [String] `openlanes:<repo>`
      def base = "#{Keys::NAMESPACE}:#{repo}"

      # Hash: node name to its `Node` JSON, refreshed every heartbeat.
      #
      # @return [String]
      def nodes = "#{base}:nodes"

      # String: the latest `Snapshot` JSON, `EX 30`. A node is alive while it exists.
      #
      # @param of [String] a node name
      # @return [String]
      def snapshot(of = node) = "#{base}:#{of}:snapshot"

      # Stream: `{seq, json}` per published snapshot.
      #
      # @param of [String]
      # @return [String]
      def board(of = node) = "#{base}:#{of}:board"

      # Stream: `{json}`, one `Command`, read by the engine through {Keys::GROUP}.
      #
      # @param of [String]
      # @return [String]
      def commands(of = node) = "#{base}:#{of}:commands"

      # Stream: `{json}`, one `Reply`.
      #
      # @param of [String]
      # @return [String]
      def replies(of = node) = "#{base}:#{of}:replies"

      # Hash: command id to its first `Reply` JSON, for redelivery.
      #
      # @param of [String]
      # @return [String]
      def done(of = node) = "#{base}:#{of}:done"

      # Hash: `seq` and `json`, the run state a person set from the page
      # (held questions and cars, queued models), so a restarted engine
      # gets it back (W6). {RunRecord} writes it; the engine flushes it to
      # `.plans/openlanes-state.json` as well.
      #
      # @param of [String]
      # @return [String]
      def run(of = node) = "#{base}:#{of}:run"

      # Pub/sub: `{json}`, one line of this node's {Engine::EventJournal},
      # mirrored after it is fsync'd. The file is the record; a subscriber
      # that misses a message reads the file.
      #
      # @param of [String]
      # @return [String]
      def journal(of = node) = "#{base}:#{of}:journal"

      # Stream: `{json}`, one `CopilotTurn`: the conversation with this
      # node's copilot (W17), the person's messages and its answers in the
      # order they were said. {Copilot} writes and reads it.
      #
      # @param of [String]
      # @return [String]
      def copilot(of = node) = "#{base}:#{of}:copilot"

      # Hash: `session`, `model`, `up` and `down`, the copilot's `claude`
      # session id and what it has spent in it. Kept beside {#copilot} so a
      # reloaded page or a restarted server carries on the same conversation
      # (W17: one session, resumed on each message).
      #
      # @param of [String]
      # @return [String]
      def copilot_session(of = node) = "#{base}:#{of}:copilot-session"

      # Stream: `{json}`, one mailbox message and the plan it belongs to,
      # what `openlanes mail send` publishes after writing `state.json`
      # (plan 003, B3). One stream per checkout; the plan rides in the entry,
      # and each plan reads it through a group of its own ({Keys#mail_group}).
      #
      # @param of [String]
      # @return [String]
      def mail(of = node) = "#{base}:#{of}:mail"

      # The consumer group one plan drains {#mail} through. Every group sees
      # every entry, so a plan's harness thread acks what it read, its own
      # or not, without taking anything from another plan's.
      #
      # @param plan [#to_s] e.g. "003.00"
      # @return [String]
      def mail_group(plan) = "mail:#{plan}"

      # Pub/sub channel: one chat's messages, joins, leaves and idle notices
      # (plan 006). Redis delivers a `PUBLISH` to every database's
      # subscribers, so the database is part of every chat channel's name: a
      # chat between nodes on database 13 never reaches a page on database 0.
      #
      # @param id [String] the chat's UUID
      # @param db [Integer] the Redis database the nodes share
      # @return [String]
      def chat_room(id, db:) = "#{chat_base(db)}:room:#{id}"

      # Pub/sub pattern matching every {#chat_room} on +db+, which each API
      # server subscribes to once, so joining a chat needs no new subscription.
      #
      # @param db [Integer]
      # @return [String]
      def chat_rooms(db:) = "#{chat_base(db).gsub(/[*?\[\]\\]/) { "\\#{it}" }}:room:*"

      # Pub/sub channel: one machine's chat inbox, where invites to it and
      # their answers arrive. Every API server for that machine listens, so
      # an invite reaches every page open there (D9).
      #
      # @param machine [String] a node id, 24 hex digits of `user@host`
      # @param db [Integer]
      # @return [String]
      def chat_inbox(machine, db:) = "#{chat_base(db)}:machine:#{machine}"

      # String: how an invite was settled (`accepted`, `declined`, `expired`),
      # `SET NX EX`, so the first answer from any page wins (D9).
      #
      # @param invite [String] the invite's UUID
      # @return [String]
      def chat_answer(invite) = "#{base}:chat:invite:#{invite}"

      # @param db [Integer]
      # @return [String]
      def chat_base(db) = "#{base}:chat:#{db}"

      # Pub/sub channel: "look again", one per project, published by
      # whoever wrote something an open page shows ({News}). Every node's
      # engine on the project publishes here, because every page shows every
      # node's board. The database is in the name for the reason it is in
      # {#chat_room}'s: a `PUBLISH` reaches every database's subscribers.
      #
      # @param db [Integer] the Redis database the nodes share
      # @return [String]
      def news(db:) = "#{base}:news:#{db}"

      # Hash: plan ordinal to that plan's running app, its process statuses
      # and a heartbeat ({Apps::Listing}). One per machine, not per
      # checkout: the app runs in a plan's worktree and the control room in
      # the main checkout, and both are this machine.
      #
      # @param machine [String] a node id, 24 hex digits of `user@host`
      # @return [String]
      def apps(machine = node.split(":").first) = "#{base}:apps:#{machine}"

      # Stream: `{json}`, one request from the Preview tab's toolbar
      # (restart, stop), read by `openlanes project start`. Not {#commands}: the
      # engine never runs an app, so it would never read them.
      #
      # @param machine [String]
      # @return [String]
      def app_commands(machine = node.split(":").first) = "#{apps(machine)}:commands"

      # String: every adapter's {Adapters::Availability} as one JSON array,
      # `EX` {Adapters::Probes::EXPIRY} (plan 040, D6). One per machine, as
      # {#apps} is: which CLIs are installed and signed in is a fact about
      # the machine, and every process on it reads the same answer.
      #
      # @param machine [String] a node id, 24 hex digits of `user@host`
      # @return [String]
      def adapters(machine = node.split(":").first) = "#{base}:adapters:#{machine}"

      # String: who is probing {#adapters} right now, `SET NX EX`
      # {Adapters::Probes::LOCK}, so the engine and the server on one
      # machine do not both start every CLI at once (D7).
      #
      # @param machine [String]
      # @return [String]
      def adapters_lock(machine = node.split(":").first) = "#{adapters(machine)}:lock"

      # String: the node name holding a plan, `SET NX EX`.
      #
      # @param ordinal [#to_s] e.g. "004.00"
      # @return [String]
      def claim(ordinal) = "#{base}:claim:#{ordinal}"
    end

    class Keys
      # What every key starts with, so `SCAN openlanes:*` finds all of it.
      NAMESPACE = "openlanes"

      # The consumer group the engine reads `commands` through.
      GROUP = "engine"

      # Lengths of {#board} and {#replies}, kept approximately.
      BOARD_LENGTH = 100
      REPLIES_LENGTH = 1000

      # Length of {#copilot}, kept approximately: a conversation the page
      # can scroll back through, not an archive.
      COPILOT_LENGTH = 500

      # Seconds a message stays in {#mail}. `state.json` is the record; the
      # stream only has to outlast a harness tick, and an hour is generous.
      MAIL_TTL = 3600

      # Seconds a snapshot outlives its last refresh.
      SNAPSHOT_TTL = 30

      # Seconds a claim outlives its last renewal.
      CLAIM_TTL = 90

      # Seconds a `done` entry is kept before it is trimmed.
      DONE_TTL = 86_400
    end
  end
end

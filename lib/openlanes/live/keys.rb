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

      # Stream: `{json}`, one `CopilotTurn`: the conversation with this
      # node's copilot (W17), the person's messages and its answers in the
      # order they were said. {Copilot} writes and reads it.
      #
      # @param of [String]
      # @return [String]
      def copilot(of = node) = "#{base}:#{of}:copilot"

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

      # Seconds a snapshot outlives its last refresh.
      SNAPSHOT_TTL = 30

      # Seconds a claim outlives its last renewal.
      CLAIM_TTL = 90

      # Seconds a `done` entry is kept before it is trimmed.
      DONE_TTL = 86_400
    end
  end
end

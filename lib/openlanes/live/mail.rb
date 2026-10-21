# frozen_string_literal: true

require "json"
require "time"

module OpenLanes
  module Live
    # Mail between agents, over Redis as well as through `state.json`
    # (plan 003, B3).
    #
    # `state.json` stays the record: `openlanes mail send` writes it first
    # and publishes here only when Redis answers, so a run without Redis
    # loses nothing. What the stream adds is delivery to the harness thread
    # beside each agent, which drains it once a second (B4) instead of
    # re-reading every plan's file.
    #
    # A stream with a consumer group per plan, not pub/sub: a message
    # published while nobody drains waits for the next drain instead of
    # vanishing. Every publish trims what is older than {Keys::MAIL_TTL}
    # and renews the key's expiry, so the stream never outgrows an hour.
    #
    # Delivery is acked once the drain's block kept it, never before: an
    # entry acked ahead of a failed write would be gone from the stream with
    # only a log line left. An entry not kept stays pending and is offered
    # again on the next drain. An ack says the bytes arrived, nothing more: a message is read when its recipient runs `openlanes mail ack`,
    # and that lands in `state.json`, never here.
    class Mail
      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @param now [Proc] wall time, which the trim's cutoff is taken from
      def initialize(store:, keys:, now: -> { Time.now })
        @store = store
        @keys = keys
        @now = now
      end

      # Publish one message that `state.json` already holds.
      #
      # @param plan [#to_s] the plan's number, e.g. "003.00"
      # @param message [OpenLanes::Plans::Mailbox::Message, Hash]
      # @return [void]
      def publish(plan:, message:)
        payload = JSON.generate("plan" => plan.to_s, "message" => wire(message))
        EventBus.for(@store).transaction do |tx|
          tx.append(@keys.mail, { json: payload })
          tx.xtrim(@keys.mail, minid: cutoff)
          tx.expire(@keys.mail, Keys::MAIL_TTL)
        end
      end

      # Every message for +plan+ that this plan's group has not had kept
      # yet: first the ones offered before and left pending, then the new.
      # Entries for other plans, and entries that are not messages, are
      # acked in this plan's group straight away, which leaves other plans'
      # groups untouched.
      #
      # With a block, each message is yielded and acked only when the block
      # returns truthy; one it returns false for, or raises on, stays pending
      # for the next drain. Without one, each is acked as it is returned.
      #
      # @param plan [#to_s]
      # @param consumer [String] who is draining, e.g. the agent's name
      # @yieldparam message [Hash] as `state.json` holds it
      # @yieldreturn [Boolean] whether it was kept
      # @return [Array<Hash>] messages as `state.json` holds them, oldest
      #   first; with a block, the ones left pending
      def drain(plan:, consumer:)
        group = @keys.mail_group(plan)
        @store.expire(@keys.mail, Keys::MAIL_TTL) if @store.xgroup_create(@keys.mail, group)
        entries = @store.xreadgroup(@keys.mail, group, consumer, id: "0") + @store.xreadgroup(@keys.mail, group, consumer)
        entries.filter_map do |entry|
          message = message_in(entry, plan.to_s)
          kept = message.nil? || !block_given? || yield(message)
          @store.xack(@keys.mail, group, entry.id) if kept
          message if message && (kept ? !block_given? : true)
        end
      end

      # Which plans have mail in the stream after +cursor+, so a drain can
      # reach a plan with nobody running on it: a worktree's `mail send` has
      # no other way into the main checkout's `state.json`, and the stream
      # forgets it after {Keys::MAIL_TTL}.
      #
      # @param cursor [String] the last stream id already looked at, "0" for
      #   all of it
      # @return [Array(Array<String>, String)] the plans, and the new cursor
      def plans_since(cursor)
        plans = []
        loop do
          entries = @store.xread(@keys.mail, id: cursor)
          break if entries.empty?

          cursor = entries.last.id
          plans.concat(entries.filter_map { plan_in(it) })
        end
        [plans.uniq, cursor]
      end

      private

      # The oldest id a publish keeps: {Keys::MAIL_TTL} seconds ago.
      #
      # @return [String]
      def cutoff = "#{((@now.call.to_f - Keys::MAIL_TTL) * 1000).to_i}-0"

      # @param message [OpenLanes::Plans::Mailbox::Message, Hash]
      # @return [Hash] string keys, `at` in ISO 8601 as `state.json` has it
      def wire(message)
        hash = message.to_h.transform_keys(&:to_s)
        hash.merge("at" => iso8601(hash["at"])).compact
      end

      # @param at [String, Time, nil]
      # @return [String, nil]
      def iso8601(at)
        return at.iso8601 if at.respond_to?(:iso8601)

        Time.parse(at.to_s).iso8601
      rescue ArgumentError
        at&.to_s
      end

      # @param entry [OpenLanes::Live::Store::Entry]
      # @return [String, nil] the plan the entry is for
      def plan_in(entry)
        data = JSON.parse(entry.fields["json"].to_s)
        data["plan"] if data.is_a?(Hash) && data["plan"].is_a?(String)
      rescue JSON::ParserError
        nil
      end

      # @param entry [OpenLanes::Live::Store::Entry]
      # @param plan [String]
      # @return [Hash, nil] the message, when the entry is one and for +plan+
      def message_in(entry, plan)
        data = JSON.parse(entry.fields["json"].to_s)
        data["message"] if data.is_a?(Hash) && data["plan"] == plan && data["message"].is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
    end
  end
end

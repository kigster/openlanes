# frozen_string_literal: true

module OpenLanes
  module Slack
    # One pass over Slack, and what is remembered between passes: which
    # question has which message, and how each stands.
    #
    # Everything here runs on the worker thread and talks to Slack through
    # the {Room}. What it learns goes to the {Outbox}, never to the store.
    #
    # Each poll fails on its own. A refusal about one message (deleted by a
    # person, too long, in a channel since archived) costs that poll and no
    # other; only what holds for every poll alike ({Room.channel_wide?}),
    # a rate limit or the network ends the cycle.
    class Asker
      # @param room [OpenLanes::Slack::Room]
      # @param outbox [OpenLanes::Slack::Outbox]
      # @param clock [Proc] wall time
      def initialize(room:, outbox:, clock:)
        @room = room
        @outbox = outbox
        @clock = clock
        @records = {}
        @missing = {}
        @said = {}
        @cursor = 0
      end

      # Take back the polls an earlier engine left open. Called on the loop
      # thread, before the worker starts.
      #
      # @return [void]
      def restore = @records = @outbox.records

      # Post what is newly asked, redraw what changed, close what was
      # settled elsewhere, and read one open poll for its answer.
      #
      # @param polls [Array<OpenLanes::Slack::Poll>] every question now asked
      # @return [void]
      def call(polls)
        asked = polls.to_h { [it.key, it] }
        asked.each { |key, poll| alone(key) { ask(key, poll) } }
        retire(asked)
        listen(asked)
      end

      private

      # Post a question that has no poll yet, or redraw one whose question
      # reads differently now. The message's place is written down before
      # its ballot goes on, so a failure there redraws this message next
      # cycle rather than posting another.
      #
      # @return [void]
      def ask(key, poll)
        record = @records[key]
        if record.nil?
          ref = @room.post(poll)
          record = keep(key, "channel" => ref.channel, "ts" => ref.ts, "state" => "open")
        end
        return unless record["state"] == "open" && record["digest"] != poll.digest

        @room.decorate(ref_of(record), poll)
        keep(key, record.merge("digest" => poll.digest, "plan" => poll.plan, "question" => poll.question))
      end

      # Polls whose question is no longer asked, and polls answered here
      # whose question still is.
      #
      # @return [void]
      def retire(asked)
        now = @clock.call.to_f
        @missing.select! { |key, _| @records.key?(key) && !asked.key?(key) }
        @records.to_a.each do |key, record|
          alone(key) { asked.key?(key) ? reconsider(key, record, asked[key], now) : lapse(key, record, now) }
        end
      end

      # The engine did not take the answer (a letter it wanted and did not
      # get, say). The reactions on the old message would only be read as
      # the same answer again, so the question is asked afresh.
      #
      # @return [void]
      def reconsider(key, record, poll, now)
        return unless record["state"] == "answered" && now - record["answered_at"].to_f > Bridge::REFUSED_AFTER

        @room.close(ref_of(record), poll, "The engine did not take that answer, so the question is asked again below.")
        forget(key)
      end

      # A question gone from the snapshot for long enough was settled
      # somewhere else.
      #
      # @return [void]
      def lapse(key, record, now)
        return if now - (@missing[key] ||= now) < Bridge::GRACE

        if record["state"] == "open" && record["question"]
          poll = Poll.new(plan: record["plan"], question: record["question"])
          @room.close(ref_of(record), poll, "Answered in the control room.")
        end
        forget(key)
      end

      # Read one open poll, a different one each cycle.
      #
      # @return [void]
      def listen(asked)
        open = @records.select { |key, record| record["state"] == "open" && asked.key?(key) }.keys
        return if open.empty?

        key = open[(@cursor += 1) % open.size]
        alone(key) { hear(key, @records[key], asked[key]) }
      end

      # Work on one poll, so that Slack refusing it stops nothing else. A
      # message that is gone is forgotten, here and in the store, so it is
      # posted afresh while its question is still asked and is not tried
      # again after a restart. Any other refusal of that one message is
      # said once and tried again next cycle.
      #
      # @param key [String]
      # @return [void]
      def alone(key)
        yield
      rescue API::Refused => e
        raise if Room.channel_wide?(e.code, posted: @records.key?(key))

        if Room::GONE.include?(e.code)
          forget(key)
          UI.log("slack: poll #{key} is gone from Slack (#{e.code}), so it is forgotten", level: :warn)
        else
          note(key, e)
        end
      end

      # Say it once, not on every cycle that is refused the same way, by
      # whichever call: a message that cannot be updated cannot be read
      # either, and that is one thing to say.
      #
      # @param refusal [OpenLanes::Slack::API::Refused]
      # @return [void]
      def note(key, refusal)
        return if @said[key] == refusal.code

        @said[key] = refusal.code
        UI.log("slack: poll #{key} skipped this cycle: #{refusal.message}", level: :warn)
      end

      # @return [void]
      def hear(key, record, poll)
        ref = ref_of(record)
        vote = @room.vote(ref, poll) or return

        @outbox.answer(poll.command(text: signed(poll, vote), stamp: record["ts"]))
        keep(key, record.merge("state" => "answered", "answered_at" => @clock.call.to_f))
        @room.close(ref, poll, ":white_check_mark: Answered by <@#{vote.user}>: #{vote.label}")
      end

      # A `blocked.md` answer is prose an agent reads, so it says where it
      # came from. The engine's own questions take a letter and nothing else.
      #
      # @return [String]
      def signed(poll, vote)
        return vote.text unless poll.question["kind"] == "block"

        "#{vote.text}\n\n(via Slack, #{@room.name_of(vote.user)})"
      end

      # @return [Hash] the record, as kept
      def keep(key, record)
        @records[key] = record
        @outbox.save(key, record)
        record
      end

      # @return [void]
      def forget(key)
        @records.delete(key)
        @missing.delete(key)
        @said.delete(key)
        @outbox.forget(key)
      end

      # @return [OpenLanes::Slack::Room::Ref]
      def ref_of(record) = Room::Ref.new(channel: record["channel"], ts: record["ts"])
    end
  end
end

# frozen_string_literal: true

require "json"

module OpenLanes
  module Slack
    # Carries a running engine's questions to Slack and the answers back.
    #
    # It is one more client of what the control room already uses. Questions
    # are read off the snapshot the engine publishes each tick, so the
    # channel is asked exactly what the page is; an answer becomes the same
    # `answer` command the page sends ({Live::Command}), so it is written to
    # `blocked.md`, signed, journalled and drained by the code that already
    # does that, and nothing about answering exists twice.
    #
    # Slack is slow and the engine's tick is not, so the two halves never
    # share a thread:
    #
    # - the loop thread calls {#offer} with each snapshot and {#call} at the
    #   top of each tick, and is the only one to touch the store, whose
    #   connection is not safe to share;
    # - a worker thread makes every Slack call ({#cycle}, which is {Asker}),
    #   and hands what it learned to the loop through the {Outbox}.
    #
    # A Slack that is down, a token that is wrong or a channel the app was
    # never invited to costs the polls and nothing else: it is logged, tried
    # again later, and the questions stay answerable on the page.
    class Bridge
      # Seconds a question may be missing from the snapshot before its poll
      # is closed. A folder renamed between two ticks drops out of one
      # snapshot, and that is not an answer.
      GRACE = 10

      # Seconds after which a question still open, although Slack answered
      # it, is taken as refused by the engine and asked again.
      REFUSED_AFTER = 30

      # Seconds to stay away after Slack or the network fails.
      BACKOFF = 30

      # @param room [OpenLanes::Slack::Room]
      # @param outbox [OpenLanes::Slack::Outbox]
      # @param interval [Numeric] seconds between cycles. Each cycle reads
      #   one poll, so 2 is 30 reads a minute, inside Slack's limit of about
      #   50. That is the read rate only: a cycle that posts a question also
      #   makes a `chat.update` and a `reactions.add` per option, and one
      #   that closes a poll a `chat.update`. A burst past the limit comes
      #   back as {API::RateLimited}, and the worker waits as Slack asks
      # @param clock [Proc] wall time
      def initialize(room:, outbox:, interval: DEFAULT_INTERVAL, clock: -> { Time.now })
        @outbox = outbox
        @asker = Asker.new(room:, outbox:, clock:)
        @interval = interval
        @lock = Mutex.new
        @polls = nil
        @stop = Thread::Queue.new
      end

      # The loop's side: this tick's questions.
      #
      # @param snapshot [Hash, nil] what {Live::Publisher#call} returned;
      #   nil when Redis was away, which says nothing about the questions
      # @return [void]
      def offer(snapshot)
        return if snapshot.nil?

        asking = Array(snapshot[:plans]).reject { Array(it[:questions]).empty? }
        plans = JSON.parse(JSON.generate(asking.map { it.slice(:ordinal, :title, :questions) }))
        polls = plans.flat_map do |plan|
          plan["questions"].map { Poll.new(plan: plan.slice("ordinal", "title"), question: it) }
        end
        @lock.synchronize { @polls = polls }
      end

      # The loop's side, at the top of a tick: write down what the worker
      # posted, and queue what people answered where {Live::Commands}, the
      # next hook, will apply it on this same tick.
      #
      # @param _dispatcher [OpenLanes::Engine::Dispatcher]
      # @return [void]
      def call(_dispatcher = nil) = @outbox.drain

      # @return [Proc] for {Engine::Dispatcher#before_tick}
      def to_proc = method(:call).to_proc

      # Take back the polls an earlier engine left open, then start asking.
      # Called on the loop thread, before the first tick.
      #
      # @return [void]
      def start
        @asker.restore
        @thread = Thread.new do
          Thread.current.name = "openlanes-slack"
          @stop.pop(timeout: pace) until @stop.closed?
        end
      end

      # @return [void]
      def stop
        @stop.close
        @thread&.join(API::TIMEOUT)
      end

      # One pass over Slack ({Asker#call}), for the questions last offered.
      # Public so the suite can drive it by hand.
      #
      # @return [void]
      def cycle
        polls = @lock.synchronize { @polls } or return
        @asker.call(polls)
      end

      private

      # One cycle, and how long to wait before the next.
      #
      # @return [Numeric] seconds
      def pace
        cycle
        @said = nil
        @interval
      rescue API::RateLimited => e
        e.retry_after
      rescue StandardError => e
        # Once per failure, not once per retry: a channel the app is not in
        # stays that way until a person invites it.
        UI.log("slack: #{e.message}; questions stay answerable in the control room", level: :warn) unless @said == e.message
        @said = e.message
        BACKOFF
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # The tick's own steps (plan 060, item 5), each handed the desk and the
      # steps it calls on, and the order they run in. The order they are
      # built in is only who needs whom.
      class Ticker
        # @param desk [Desk]
        # @param options [Options] read for `rescan` and `watch`
        def initialize(desk, options)
          @desk = desk
          build_tick(options.rescan)
          build_steps(options.watch)
        end

        attr_reader :poll, :rename, :rows, :settle, :start, :assign, :lanes, :rulings, :merges, :sweeps, :watching, :unblocking

        # One pass of every step, in order. `convert` turns prose questions
        # into choices between the drain and the polls.
        #
        # @param convert [#call]
        # @return [void]
        def call(convert)
          drain
          convert.call
          look
          act
        end

        private

        def drain
          @settle.reap
          @lanes.finish_discards
          @unblocking.call
        end

        def look
          @poll.poll
          @poll.ask_for_time
          @poll.drain_mail
          @watching&.call
          @rulings.arbitrate
          @rulings.settle_verifications
        end

        def act
          @merges.call
          @sweeps.call
          quit = Execution::Control
          # On threads: a kill waits out TERM before KILL, and the board must not.
          @desk.running.each { |job| Thread.new { job.handle.kill!(grace: 0, reason: :quit) } } if quit.overdue?
          @assign.dispatch unless quit.quit? || @assign.resting?
        end

        def build_tick(rescan)
          @poll = Poll.new(@desk)
          @rename = Rename.new(@desk)
          @rows = Rows.new(@desk, waiting_on: -> { @watching&.waiting_on || {} })
          @settle = Settle.new(@desk, rename: @rename, poll: @poll, row: @rows.method(:row_for))
          @start = Start.new(@desk, rename: @rename, settle: @settle)
          @assign = Assign.new(@desk, start: @start, rescan:)
          @lanes = Lanes.new(@desk)
          @rulings = Rulings.new(@desk)
        end

        # The tick's polls and drains, each a class of its own (045), handed
        # what they need of the loop as callables.
        def build_steps(watch)
          context = Steps::Context.new(runner: @desk.runner,
            busy: @desk.method(:untouchable),
            wake: @desk.method(:wake!),
            reopen: ->(ordinal) { @desk.finished_plans.delete(ordinal) },
            snapshot: watch&.snapshot)
          @merges = Steps::Merges.new(context)
          @sweeps = Steps::Sweeps.new(context, resolve: @start.method(:resolve_conflict))
          @watching = watch && Steps::Watch.new(context, watch:, finishes: @desk.finishes, state: @desk.state_file)
          @unblocking = @desk.unblocking = Unblocking.drainer(context, history: method(:clear_blocked))
        end

        # A drained plan's agents get their rounds back: a block is a
        # question, not the agent running out of turns.
        def clear_blocked(ordinal)
          @desk.mutex.synchronize do
            @desk.history.each { |(plan, _), entries| entries.reject! { it[:status] == "Blocked" } if plan == ordinal }
          end
        end
      end
    end
  end
end

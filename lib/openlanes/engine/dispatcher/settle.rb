# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # Makes one {Runner::Attempt} of each finished job ({Verdict}, {Stops}),
      # written ({Records}), announced and left on the board ({Linger}). The
      # folder's move is {Rename}'s.
      class Settle < Step
        # `row:` [#call] gives a job's row on the board.
        def initialize(desk, rename:, poll:, row:)
          super(desk)
          @rename = rename
          @poll = poll
          @account = Account.new(desk)
          readers(desk, rename, Stops.new(desk))
          @records = Records.new(desk)
          @announcement = Announcement.new(desk)
          @linger = Linger.new(desk, row:)
        end

        # @return [void] see {Replacement#end_replacements}
        def end_replacements(ordinal) = @replacement.end_replacements(ordinal)

        # @return [void]
        def reap
          running.select(&:finished?).each { reap_one(it) }
        end

        private

        # The steps that read what a round came to, sharing one {Stops}.
        def readers(desk, rename, stops)
          @replacement = Replacement.new(desk, stops:)
          @special = Special.new(desk, stops:, replacement: @replacement)
          @verdict = Verdict.new(desk, rename:, stops:, signing: Signing.new(desk, rename:, stops:))
        end

        def reap_one(job)
          before_settling(job)
          attempt = settle(job)
          @announcement.call(job, attempt)
          feed.ended(job, attempt)
          hand_back(job)
          attempts << attempt
          close_extension(job)
          @linger.call(job, attempt)
        end

        # Before its own outcome is settled, so the last partner's advance
        # starts from the state the pair held at; and what it printed since
        # the last tick first, so a killed round keeps every line it got out.
        def before_settling(job)
          running.delete(job)
          @rename.apply_hold(plan_of(job))
          @poll.record_journal(job)
          feed.progress(job)
        end

        # A requeue, or a compaction that stopped the agent and then could not
        # happen, hands the round back: the stop was a person's choice.
        def hand_back(job)
          requeued = requeues.delete(job.key)
          forget_round(job) if requeued || job.handle.compaction&.restart
        end

        # @return [OpenLanes::Engine::Runner::Attempt]
        def settle(job)
          base = @account.call(job)
          special = @special.call(job, base) and return special
          return base.with(note: job.result.note) if runner.dry_run?

          attempt = @verdict.call(job, base)
          @records.write(job, attempt)
          @replacement.call(job, attempt, job.result)
        end

        # An ended round needs no more time: its open request is closed, not left on the page.
        def close_extension(job)
          ladder.forget(job)
          return if runner.dry_run?

          subject = fresh(job.task) or return
          extensions.close!(subject.feature.path, job.task.agent.name, job.state)
        end
      end
    end
  end
end

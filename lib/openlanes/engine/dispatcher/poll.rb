# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # What the running agents have written since the last tick, read and
      # kept: each one's latest ledger line and spend into the state file,
      # its session and journal lines into the plan's `state.json`, and the
      # mail addressed to its plan. It also notices an agent near the end of
      # its clock. Nothing here starts, stops or renames anything.
      class Poll < Step
        # @return [void]
        def poll
          running.each do |job|
            reading = read_ledger(job.task)
            entry = Plans::Ledger.last_for(reading, job.task.agent.name)
            job.file = entry&.file || job.file
            job.status = entry&.status
            record_session(job)
            record_journal(job)
            feed.progress(job)
            state_file&.record(job.task.subject.feature.ordinal.to_s,
              agent:  job.task.agent.name,
              round:  job.task.round,
              status: entry&.status || "Started",
              file:   job.file,
              up:     job.up,
              down:   job.down,
              pid:    job.handle.pid,
              **{ session: job.handle.session }.compact)
          end
        end

        # Each running agent near the end of its clock asks for more, and is
        # given it once on its own. Read only in the last {Extensions::ASK_AT}
        # seconds, so the folder is looked up then and not on every tick.
        #
        # @return [void]
        def ask_for_time
          return if runner.dry_run?

          running.each do |job|
            left = job.handle.remaining
            next unless left && left <= Extensions::ASK_AT

            subject = fresh(job.task) or next
            extensions.watch(job, subject.feature.path)
          end
        end

        # Messages published to Redis, kept in their plan's `state.json`
        # unless that file already has them. Every plan with an agent running
        # is drained, and so is every plan the stream has mail for, running or
        # not: a worktree's `mail send` reaches the main checkout only through
        # the stream, which forgets it after an hour. A plan stays on the list
        # until nothing of its mail is left pending.
        #
        # A message is acked once it is kept, or once it proves it never can
        # be (no body, no single sender), since retrying an invalid message
        # every second for an hour would only repeat the log line. One whose
        # plan this checkout cannot find stays pending and is tried next tick.
        #
        # Only delivery: nothing here reads whether a message was acked by its
        # reader, and no assignment turns on it (D3). Redis going away mid-run
        # costs the drain, never the tick.
        #
        # @return [void]
        def drain_mail
          return if mail.nil? || runner.dry_run?

          found, @mail_cursor = mail.plans_since(@mail_cursor || "0")
          @mail_plans = (@mail_plans || Set.new) | found
          plans = running.map { plan_of(it).to_s } | @mail_plans.to_a
          plans.each do |ordinal|
            pending = mail.drain(plan: ordinal, consumer: "harness") { |message| keep_mail(ordinal, message) }
            @mail_plans.delete(ordinal) if pending.empty?
          end
        rescue Live::Unavailable, SystemCallError => e
          UI.log("mail not drained: #{e.message}", level: :warn)
        end

        # The journal lines (M2) the agent printed since the last look, into
        # the plan's `state.json`, as they arrive rather than when the round
        # ends, so a round that is killed keeps what it already said. The
        # executor's thread only collects them; writing happens here, on the
        # loop's, against the folder as it is named now.
        #
        # A line that is not a valid entry is dropped and said so in the log:
        # the agent believes it remembered it, and only the log can tell a
        # person it did not.
        #
        # The place in the list moves on only once the lines are written. A
        # folder not found this tick, or a `state.json` that cannot be written
        # right now, leaves them for the next tick to try again, rather than a
        # hole in the journal the agent believes it kept.
        #
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [void]
        def record_journal(job)
          lines = job.journal || []
          return if job.rebase || runner.dry_run? || lines.size <= job.journaled.to_i

          fields = job.task.log_fields
          entries, rejected = lines[job.journaled.to_i..].partition { it.is_a?(Plans::Journal::Entry) }
          unless entries.empty?
            subject = fresh(job.task) or
              return UI.log("journal not written yet: plan folder not found", level: :warn, **fields)

            job.journal_round, refused = Plans::PlanState.for(subject.feature.path)
                                                         .journal!(agent: job.task.agent.name,
                                                           entries:,
                                                           number: job.journal_round,
                                                           round: job.task.round,
                                                           state: job.from)
            rejected += refused
          end
          job.journaled = lines.size
          rejected.each { UI.log("journal line ignored, #{it.reason}: #{it.line[0, 160]}", level: :warn, **fields) }
        rescue SystemCallError, OpenLanes::Error => e
          UI.log("journal not written yet: #{e.message}", level: :warn, **job.task.log_fields)
        end

        private

        # @param ordinal [String]
        # @param message [Hash]
        # @return [Boolean] whether the stream may forget it
        def keep_mail(ordinal, message)
          subject = fresh_by(ordinal) or return false
          Plans.mailbox(subject.feature.path).deliver(message)
          true
        rescue OpenLanes::Error => e
          UI.log("mail not kept: #{e.message}", level: :warn, plan: ordinal)
          true
        end

        # A round's session id goes into its stage the moment the stream names
        # it, not only when the round settles: a person resuming an agent by
        # hand is most often doing it while the round is still running, or
        # after the harness died under it.
        #
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [void]
        def record_session(job)
          session = job.handle&.session
          return if session.nil? || job.recorded_session == session || job.rebase

          subject = fresh(job.task) or return
          stage!(subject, job.task.agent, job.task.round, session:)
          job.recorded_session = session
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # Makes one {Runner::Attempt} of each job that finished: what the
      # agent's ledger line, the executor's result and the harness's own
      # stops add up to, written to both records, announced, and left on
      # the board for {LINGER} seconds. The folder's move is {Rename}'s.
      class Settle < Step
        # @param desk [Desk]
        # @param rename [Rename]
        # @param poll [Poll]
        # @param row [#call] a job's row on the board
        def initialize(desk, rename:, poll:, row:)
          super(desk)
          @rename = rename
          @poll = poll
          @row = row
        end

        # @return [void]
        def reap
          running.select(&:finished?).each do |job|
            running.delete(job)
            # Before its own outcome is settled, so the last partner's advance
            # starts from the state the pair held at.
            apply_hold(plan_of(job))
            # What it printed since the last tick, before anything is made of
            # its outcome: a killed round keeps every line it got out.
            record_journal(job)
            feed.progress(job)
            attempt = settle(job)
            announce(job, attempt)
            feed.ended(job, attempt)
            # A requeue, or a compaction that stopped the agent and then could
            # not happen, hands the round back: the stop was a person's choice.
            requeued = requeues.delete(job.key)
            forget_round(job) if requeued || job.handle.compaction&.restart
            attempts << attempt
            close_extension(job)
            row = @row.call(job)
            recent << { at: UI.monotonic, row: row.with(state: attempt.ok ? :done : :failed,
              message: attempt.note,
              history: Board::Row.remember(row.history, attempt.note),
              remaining: nil,
              phase: nil,
              running: [],
              bold: !attempt.ok) }
            # `to:` names the state the plan moved to, on the terminal and in the log.
            moved = Plans::STATUS_BY_KEY[attempt.to]&.to_s if attempt.advanced?
            UI.log(attempt.ok ? "finished: #{attempt.note}" : "failed: #{attempt.note}",
              level: attempt.ok ? :info : :warn,
              **job.task.log_fields,
              **{ to: moved }.compact)
          end
        end

        # A new review round opened: a replacement the last one owed is dropped.
        #
        # @param ordinal [String]
        # @return [void]
        def end_replacements(ordinal)
          executor = runner.executor
          return unless executor.respond_to?(:end_replacements)

          executor.end_replacements(ordinal)
          models.delete_if { |(plan, _), _| plan == ordinal }
        end

        private

        def_delegators :@rename, :complete, :park, :assessed, :apply_hold
        def_delegators :@poll, :record_journal

        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [OpenLanes::Engine::Runner::Attempt]
        def settle(job)
          task = job.task
          agent = task.agent
          ordinal = task.subject.feature.ordinal.to_s
          result = job.result
          base = attempt_for(job)
          # Before anything reads the ledger: a resolution signs nothing, so
          # whatever the ledger holds is the plan's previous round, not this one.
          return swept(job, base, result) if job.sweep
          return base.with(ok: false, note: "rebase: #{result.message}") if job.rebase && result.is_a?(Exception)
          return base if job.rebase
          return substitute(job, crashed(job, base, result), result) if result.is_a?(Exception)
          return app_did_not_start(job, base, result) if result.is_a?(Verification::AppSession::Failed)
          return base.with(note: result.note) if runner.dry_run?

          reading = read_ledger(task)
          entry = Plans::Ledger.last_for(reading, agent.name)
          entry = nil if entry && entry.round != task.round
          problems = reading.problems.map { |p| "#{p.file}:#{p.line} unreadable ledger line" }

          attempt = if (why = stopped_for(ordinal))
                      stopped_by_harness(job, base, why)
                    elsif assessor?(agent) && !(result.ok && entry&.completed?)
                      # No verdict is `manual` (P4), never a second try at `auto`.
                      write_interrupted(fresh(task), agent, task.round, reason_for(result)) if fresh(task) && result.killed
                      assessed(job, base, nil)
                    elsif result.killed || (result.ok && (entry.nil? || entry.status == "Started"))
                      verify_and_sign(job, base, reason_for(result))
                    elsif !result.ok
                      fresh(task)&.then { harness_resume(it, agent, task.round, result.note, phrase: job.message) }
                      remember(ordinal, agent.name, job.state, "Interrupted", task.round)
                      base.with(ok: false, note: result.note)
                    elsif entry.completed?
                      complete(job, base, entry, reading)
                    elsif entry.blocked?
                      park(job, base, entry)
                    else
                      remember(ordinal, agent.name, job.state, entry.status, task.round)
                      base.with(status: entry.status, note: retry_note(agent, entry))
                    end
          attempt = attempt.with(note: "#{attempt.note}; #{problems.join(", ")}") unless problems.empty?
          attempt = attempt.with(to: fresh(task)&.status&.key || attempt.to)
          # One outcome, written to both records. The engine's state file once
          # defaulted a failed round to Completed while state.json said
          # Interrupted, so the page and the plan disagreed about the same round.
          outcome = attempt.status || (attempt.ok ? "Completed" : "Interrupted")
          if (settled = fresh(task))
            stage!(settled,
              agent,
              task.round,
              status:      outcome,
              to:          attempt.to.to_s,
              finished_at: clock.now.iso8601,
              up:          attempt.up.to_i,
              down:        attempt.down.to_i,
              seconds:     attempt.seconds.to_f.round(1),
              note:        attempt.note.to_s,
              session:     job.handle&.session)
          end
          state_file&.record(ordinal,
            agent:    agent.name,
            round:    task.round,
            status:   outcome,
            exit:     attempt.ok ? "ok" : attempt.note,
            ended_at: clock.now.iso8601,
            up:       attempt.up,
            down:     attempt.down,
            # An agent that ends before the first poll is otherwise never named here.
            **{ session: job.handle&.session }.compact)
          substitute(job, attempt, result)
        end

        # A reviewer that crashed, timed out or ended without a verdict runs
        # its round again, once, on the main coding agent, and that verdict
        # counts as its own (D14 in plan 031). The round is handed back, so
        # the replacement runs even when the reviewer had none left; the
        # replacement's own failure is an ordinary one. A person's stop, the
        # harness's, and a plan that has left review are not failures to make
        # up for.
        #
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @param attempt [OpenLanes::Engine::Runner::Attempt]
        # @param result [OpenLanes::Execution::Executor::Result, Exception]
        # @return [OpenLanes::Engine::Runner::Attempt]
        def substitute(job, attempt, result)
          task = job.task
          agent = task.agent
          ordinal = plan_of(job)
          executor = runner.executor
          return attempt unless agent.phase.to_s == REVIEW_PHASE && executor.respond_to?(:replace)

          if executor.replacing?(ordinal, agent.name)
            executor.replace(ordinal, agent.name, on: false)
            models.delete([ordinal, agent.name])
            return attempt
          end
          return attempt unless replaceable?(job, attempt, result)

          main = Agents::Dealing.current.main
          executor.replace(ordinal, agent.name)
          models.delete([ordinal, agent.name])
          resume(ordinal, agent.name)
          fresh(task)&.then { stage!(it, agent, task.round, replaced_by: main) }
          UI.log("runs again on #{main}", **task.log_fields)
          attempt.with(note: "#{attempt.note}; runs again on #{main}")
        end

        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @param attempt [OpenLanes::Engine::Runner::Attempt]
        # @param result [OpenLanes::Execution::Executor::Result, Exception]
        # @return [Boolean] whether the attempt failed in a way {#substitute} makes up for
        def replaceable?(job, attempt, result)
          return false if attempt.ok || attempt.status.to_s.start_with?("Blocked")
          return false if stopped_for(plan_of(job)) || Execution::Control.interrupted?
          return false if result.respond_to?(:killed) && %i[key quit].include?(result.killed)

          %i[ready_for_review in_review].include?(fresh(job.task)&.status&.key)
        end

        # @param ordinal [String]
        # @return [String, nil] why the harness stopped the plan's agents, if it did
        def stopped_for(ordinal)
          return "claim lost to another machine" if fenced.include?(ordinal)

          "discarded by a person" if discarding.key?(ordinal)
        end

        # An agent stopped because its plan was discarded or taken by another
        # machine: what it left is about to be thrown away, or is no longer
        # this node's to judge, so the harness signs nothing for it.
        #
        # @return [OpenLanes::Engine::Runner::Attempt]
        def stopped_by_harness(job, base, why)
          task = job.task
          subject = fresh(task)
          if subject
            harness_resume(subject, task.agent, task.round, why, phrase: job.message)
            write_interrupted(subject, task.agent, task.round, why)
          end
          remember(plan_of(job), task.agent.name, job.state, "Interrupted", task.round)
          base.with(ok: false, status: "Interrupted", note: why)
        end

        # @param result [OpenLanes::Execution::Executor::Result]
        # @return [String]
        def reason_for(result)
          case result.killed
          when :key then "killed by harness after #{KILL_GRACE}s grace"
          when :timeout then "timed out, killed #{Execution::Clock::GRACE}s after STOP"
          when :quit then "interrupted, killed #{Execution::Control::GRACE}s after #{Execution::Control.interrupted? ? "ctrl-c" : "q"}"
          else Execution::Control.interrupted? ? "interrupted by ctrl-c" : "no closing ledger line"
          end
        end

        # @return [String]
        def retry_note(agent, entry)
          left = rounds_for(agent) - entry.round
          left.positive? ? "#{entry.status}; #{left} round#{"s" unless left == 1} left" : "#{entry.status}; no rounds left"
        end

        # The agent stopped without saying it finished. If the state it was
        # advancing to is justified by what is on disk, the work happened and
        # the harness signs for it in state.json, saying why it had to.
        #
        # @return [OpenLanes::Engine::Runner::Attempt]
        def verify_and_sign(job, base, reason)
          task = job.task
          agent = task.agent
          subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
          # Read before the harness's own Interrupted line lands, which would
          # otherwise be the "last ledger line" the resume record quotes.
          last = last_line(subject, agent)
          write_interrupted(subject, agent, task.round, reason)
          target = agent.advances_to&.then { subject.machine.onward(it) }
          if target && subject.machine.may?(target)
            successor = runner.agents.for_status(Plans::STATUS_BY_KEY.fetch(target)).first&.name
            Plans::PlanState.for(subject.feature.path).sign!(agent: agent.name,
              round:      task.round,
              status:     "Completed",
              note:       "signed by harness: work verified on disk",
              next_agent: successor)
            entry = Plans::Ledger.last_for(read_ledger(task), agent.name)
            complete(job, base.with(note: "#{reason}; signed by harness"), entry, read_ledger(task))
          else
            harness_resume(subject, agent, task.round, reason, last:, phrase: job.message)
            remember(subject.feature.ordinal.to_s, agent.name, job.state, "Interrupted", task.round)
            base.with(ok: false, status: "Interrupted", note: "#{reason}; #{retry_note(agent, Plans::Ledger::Entry.new(at: clock.now, agent: agent.name, status: "Interrupted", round: task.round, file: "", line: 0))}")
          end
        end

        # A sweep's resolution ended (U3); the keeper says what follows.
        #
        # @return [OpenLanes::Engine::Runner::Attempt]
        def swept(job, base, result)
          conflict = job.sweep
          report = runner.upkeep.finished(conflict, job.task.checkout, result, held: rebases.hold(conflict.ordinal))
          base.with(**report.to_h.compact)
        end

        # The app did not come up, so verifier never ran: rejected all the same
        # (M1), with the failing process's last lines.
        #
        # @param result [OpenLanes::Engine::Verification::AppSession::Failed]
        # @return [OpenLanes::Engine::Runner::Attempt]
        def app_did_not_start(job, base, result)
          task = job.task
          subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
          remember(plan_of(job), task.agent.name, job.state, "Completed", task.round)
          rejected = runner.verification.reject(task, subject, why: result.to_markdown)
          note = rejected&.note || "no open pull request to reject"
          base.with(ok: !rejected.nil?, status: "Completed", to: rejected&.to || job.state, note: "#{result.headline}; #{note}")
        end

        # @return [OpenLanes::Engine::Runner::Attempt]
        def crashed(job, base, error)
          fresh(job.task)&.then { harness_resume(it, job.task.agent, base.round, error.message.lines.first.to_s.strip, phrase: job.message) }
          remember(base.ordinal, base.agent, job.state, "Interrupted", base.round)
          base.with(ok: false, note: error.message.lines.first.to_s.strip)
        end

        # The durable record of one settled attempt: `agent_finished` always,
        # `block_raised` when the agent signed Blocked, `failure` when the
        # attempt failed. Fire and forget: the sink never raises.
        #
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @param attempt [OpenLanes::Engine::Runner::Attempt]
        # @return [void]
        def announce(job, attempt)
          events = runner.events
          fields = event_fields(job)
          invocations.delete(job.key)
          return unless events.enabled?

          status = attempt.status || (attempt.ok ? "Completed" : "Interrupted")
          usage = Events::Usage.from(adapter: fields[:adapter],
            model: fields[:model],
            totals: { up: attempt.up, down: attempt.down },
            subagents_spawned: attempt.subagents.to_i)
          events.record(:agent_finished, **fields, status:, duration_s: attempt.seconds, **usage.to_h.transform_keys(&:to_sym))
          events.record(:block_raised, **fields, blocks: blocked_count(job)) if status.start_with?("Blocked")
          return if attempt.ok

          error = job.result.is_a?(Exception) ? job.result.class.name : "AttemptFailed"
          events.record(:failure, **fields, error_class: error)
        rescue StandardError => e
          UI.log("event not recorded", plan: job.task.subject.feature.ordinal.to_s, error: e.class.name)
        end

        # @return [Integer] the open `## B<n>` questions the plan now carries
        def blocked_count(job)
          subject = fresh(job.task) or return 0
          path = File.join(subject.feature.path, "blocked.md")
          File.file?(path) ? File.read(path).scan(Plans::OPEN_BLOCK).size : 0
        end

        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [OpenLanes::Engine::Runner::Attempt]
        def attempt_for(job)
          task = job.task
          result = job.result
          spend = ->(field) { result.respond_to?(field) ? result.public_send(field) : 0 }
          Runner::Attempt.new(ordinal: task.subject.feature.ordinal.to_s,
            agent: task.agent.name,
            from: job.from,
            to: job.from,
            ok: result.respond_to?(:ok) ? !!result.ok : false,
            note: result.respond_to?(:note) ? result.note.to_s : "",
            up: spend.call(:up),
            down: spend.call(:down),
            subagents: spend.call(:subagents),
            delegated: spend.call(:delegated),
            seconds: spend.call(:seconds),
            round: task.round,
            file: job.file || task.agent.ledger.first.to_s,
            model: model_for(task.agent, task.subject),
            status: job.status)
        end

        # A round that has ended needs no more time, however it ended: its open
        # request, if it asked, is closed rather than left on the page.
        #
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @return [void]
        def close_extension(job)
          return if runner.dry_run?

          subject = fresh(job.task) or return
          extensions.close!(subject.feature.path, job.task.agent.name, job.state)
        end
      end
    end
  end
end

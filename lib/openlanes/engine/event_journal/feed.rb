# frozen_string_literal: true

module OpenLanes
  module Engine
    class EventJournal
      # What the dispatcher tells the progress journal (S9): the run's own
      # events, and each agent's in-flight picture, which a replay rebuilds.
      # A run that keeps no journal hands this nil, and every call is a no-op.
      class Feed
        # @param journal [EventJournal, nil]
        def initialize(journal)
          @journal = journal
          @seen = {}
        end

        # One event, when the run keeps a journal. A disk that refuses the
        # write is reported, not raised: the agents already running are
        # worth more than the record of them.
        #
        # @param kind [Symbol]
        # @param fields [Hash]
        # @return [void]
        def append(kind, **fields)
          @journal&.append(kind, **fields)
        rescue SystemCallError, IOError => e
          UI.log("journal write failed: #{e.class}: #{e.message}", level: :warn)
        end

        # The agent's pid and start time the first time it is seen, its
        # session id once its stream names it, and the trace's size whenever
        # it grew.
        #
        # @param job [Dispatcher::Job]
        # @return [void]
        def progress(job)
          return unless @journal

          handle = job.handle
          pid = handle&.pid or return
          seen = (@seen[job.key] ||= {})
          started(job, seen) unless seen[:pid] == pid
          session(job, seen)
          offset(job, seen)
        end

        # @param job [Dispatcher::Job]
        # @param attempt [Runner::Attempt]
        # @return [void]
        def ended(job, attempt)
          return unless @journal

          who = who(job)
          append(:agent_ended, **who, exit: attempt.ok ? 0 : 1, note: attempt.note.to_s) if @seen.delete(job.key)
          return unless attempt.advanced?

          append(:transition, plan: who[:plan], from: attempt.from.to_s, to: attempt.to.to_s, event: event_between(attempt.from, attempt.to))
        end

        private

        # @return [Hash{Symbol => String}]
        def who(job) = { plan: job.task.subject.feature.ordinal.to_s, agent: job.task.agent.name }

        # @return [void]
        def started(job, seen)
          handle = job.handle
          seen.replace(pid: handle.pid, session: handle.session, offset: 0)
          append(:agent_started,
            **who(job),
            round:       job.task.round,
            pid:         handle.pid,
            started_at:  Execution::ProcessStart.of(handle.pid)&.utc&.iso8601,
            session_id:  handle.session,
            output_file: handle.trace)
        end

        # @return [void]
        def session(job, seen)
          session = job.handle.session
          return unless session && seen[:session] != session

          seen[:session] = session
          append(:agent_session, **who(job), session_id: session)
        end

        # @return [void]
        def offset(job, seen)
          trace = job.handle.trace
          offset = trace && File.exist?(trace) ? File.size(trace) : 0
          return unless offset > seen[:offset]

          seen[:offset] = offset
          append(:agent_offset, **who(job), offset:)
        end

        # The aasm event that moved +from+ to +to+. A destination names one
        # forward event, but a retreat lands on the same states by
        # `step_back`, so the edge, not the destination alone, says which fired.
        #
        # @return [String]
        def event_between(from, to)
          from = from.to_sym
          to = to.to_sym
          return "step_back" unless Plans::StateMachine.inbound.fetch(to, []).include?(from)

          Plans::StateMachine.event_for.fetch(to).to_s
        end
      end
    end
  end
end

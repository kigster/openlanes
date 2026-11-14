# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Poll < Step
        # One running job, looked at once a tick: its latest ledger line read
        # back onto it, its session and journal kept, its progress fed to the
        # board, and all of it written into the state file for a restart.
        class Sighting < Step
          # @param desk [Desk]
          # @param journal [Journal]
          def initialize(desk, journal:)
            super(desk)
            @journal = journal
          end

          # @param job [OpenLanes::Engine::Dispatcher::Job]
          # @return [void]
          def call(job)
            entry = read_back(job)
            record_session(job)
            @journal.call(job)
            feed.progress(job)
            state_file&.record(job.task.subject.feature.ordinal.to_s, **recorded(job, entry))
          end

          private

          # The agent's latest ledger line, its file and status put on the job.
          def read_back(job)
            entry = Plans::Ledger.last_for(read_ledger(job.task), job.task.agent.name)
            job.file = entry&.file || job.file
            job.status = entry&.status
            entry
          end

          def recorded(job, entry)
            handle = job.handle
            { agent: job.task.agent.name, round: job.task.round, status: entry&.status || "Started", file: job.file,
              up: job.up, down: job.down, pid: handle.pid, **{ session: handle.session }.compact }
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
end

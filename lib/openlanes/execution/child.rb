# frozen_string_literal: true

module OpenLanes
  module Execution
    # One `claude` process the harness started and therefore owns.
    #
    # `TTY::Command` never exposes the pid it spawned, so the executor used to
    # find its child by scraping `ps` for a fresh `claude` under this process
    # and could never safely signal it. Kill (`k`) and the sixty-second
    # backstop after STOP both need a pid that is certainly ours, so the
    # process is spawned here and the pid kept.
    #
    # stderr is folded into the same pipe as stdout: `claude` prints the cause
    # of a failure there, and the transcript keeps non-JSON lines for exactly
    # that reason.
    #
    # The process leads a process group of its own, and every stop is sent to
    # the whole group. A SIGKILL aimed at `claude` alone once left the shell
    # its Bash tool had started (and the `eza` an `ls` alias ran in it)
    # holding the write end of this pipe: the reader never saw end of file,
    # and `--timeout 600` ended nothing. The group is also why a terminal's
    # Ctrl-C no longer reaches an agent directly; the harness forwards its
    # own stop instead, and {.terminate_all} catches a harness that exits
    # before its agents have.
    class Child
      # Seconds between TERM and KILL in {#terminate}: long enough for a
      # process to flush and exit, short enough that a stop is a stop.
      TERM_GRACE = 5

      # Seconds {#terminate} waits, after KILL, for the reader to reach end of
      # file on its own before closing the pipe under it. Only a process that
      # left the group, by `setsid` or a daemonising double fork, can still be
      # holding the pipe by then.
      DRAIN_GRACE = 1

      # How often {#terminate} looks again while it waits.
      POLL = 0.05

      @live = []
      @mutex = Mutex.new

      class << self
        # @param argv [Array<String>]
        # @param chdir [String, nil]
        # @param env [Hash{String => String}] what the adapter adds on top of
        #   {.environment}, e.g. claude's autocompact threshold
        # @return [OpenLanes::Execution::Child]
        def spawn(argv, chdir: nil, env: {})
          reader, writer = IO.pipe
          options = { out: writer, err: writer, in: File::NULL, unsetenv_others: true, pgroup: true }
          options[:chdir] = chdir if chdir
          pid = Process.spawn(environment.merge(env), *argv, **options)
          writer.close
          track(new(pid:, reader:))
        end

        # The environment the child starts in: the one Bundler was loaded under,
        # less what Bundler itself put there. `exe/openlanes` pins `BUNDLE_GEMFILE`
        # to its own Gemfile and `bundler/setup` adds `-rbundler/setup` to
        # `RUBYOPT`; a child that inherited them would run every `bundle exec`,
        # `standardrb` and `alock` against the harness's checkout instead of the
        # worktree it was handed, and be told the gems that worktree's Gemfile adds
        # are "not currently included in the bundle". Bundler knows exactly what it
        # changed, so it is asked; without Bundler there is nothing to strip.
        #
        # @return [Hash{String => String}]
        def environment
          defined?(::Bundler) ? ::Bundler.unbundled_env : ENV.to_h
        end

        # @return [Array<OpenLanes::Execution::Child>] spawned and not yet reaped
        def live = @mutex.synchronize { @live.dup }

        # KILL every group still running. Registered with `at_exit`, so a
        # second Ctrl-C, which raises in the harness and ends it at once, takes
        # its agents down with it now that the terminal's own SIGINT no
        # longer reaches them.
        #
        # A child stays here after its leader is reaped for as long as its
        # group has members: a grandchild that ignores TERM and let go of the
        # pipe outlives the leader, and this is what still reaches it.
        #
        # @return [void]
        def terminate_all = live.each { it.kill("KILL") }

        # @param child [OpenLanes::Execution::Child]
        # @return [void]
        def forget(child) = @mutex.synchronize { @live.delete(child) }

        private

        # @param child [OpenLanes::Execution::Child]
        # @return [OpenLanes::Execution::Child]
        def track(child)
          @mutex.synchronize do
            @at_exit ||= at_exit { terminate_all }
            @live.reject!(&:finished?)
            @live << child
          end
          child
        end
      end

      # @param pid [Integer]
      # @param reader [IO]
      def initialize(pid:, reader:)
        @pid = pid
        @reader = reader
        @status = nil
        @terminating = false
        @emptied = false
        @guard = Mutex.new
      end

      # @return [Integer]
      attr_reader :pid

      # Read until the process closes its end. Runs on the caller's thread;
      # the executor reads on the same thread it always did.
      #
      # @yieldparam text [String] whatever arrived, possibly a partial line
      # @return [void]
      def each_chunk
        loop { yield @reader.readpartial(65_536) }
      rescue IOError
        # End of file, or {#terminate} closed the pipe under a reader that
        # would otherwise have waited on it forever.
        @reader.close unless @reader.closed?
      end

      # @return [Process::Status]
      def wait
        @status ||= begin
          _, status = Process.wait2(pid)
          status
        end
      rescue Errno::ECHILD
        @status
      ensure
        self.class.forget(self) if finished?
      end

      # @return [Boolean] reaped, and nothing left in its group
      def finished? = !@status.nil? && !group?

      # Signal the whole group: the agent and everything it started.
      #
      # The group is signalled even after its leader has been reaped. A member
      # that ignored TERM and let go of the pipe outlives the leader, and POSIX
      # does not hand a group's id out as a pid while the group has members,
      # so `-pid` still means this group. Once it answers ESRCH the group is
      # empty, the id is free, and it is never signalled again.
      #
      # @param signal [String]
      # @return [void]
      def kill(signal = "KILL")
        return if @emptied

        Process.kill(signal, -pid)
      rescue Errno::ESRCH
        @emptied = true
      rescue Errno::EPERM
        # Not ours to signal, so not ours to end.
      end

      # The guarantee behind every stop: TERM to the group, KILL to whatever
      # is left after +grace+, and the pipe closed if something outside the
      # group still holds it, so the reader always finishes.
      #
      # Once only: the dispatcher asks again on every tick past a quit's
      # deadline, and a second caller has nothing to add to the first.
      #
      # The leader being reaped mid-grace does not cut it short: the reader
      # sees end of file as soon as the leader dies, and a member that
      # ignored TERM is still there to KILL. The caller's thread must be left
      # to finish; {Clock#stop} waits for an expiry under way for that reason.
      #
      # @param grace [Numeric] seconds between TERM and KILL
      # @param drain [Numeric] seconds after KILL before the pipe is closed
      # @return [void]
      def terminate(grace: TERM_GRACE, drain: DRAIN_GRACE)
        return if @guard.synchronize { @terminating.tap { @terminating = true } }

        kill("TERM")
        await(grace) { !group? }
        kill("KILL")
        await(drain) { @reader.closed? }
        @reader.close unless @reader.closed?
      rescue IOError
        # The reader closed it first.
      end

      # @return [Boolean]
      def alive?
        return false if @status

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end

      private

      # @return [Boolean] whether anything in the group, a zombie leader
      #   included, is still there
      def group?
        return false if @emptied

        Process.kill(0, -pid)
        true
      rescue Errno::ESRCH
        @emptied = true
        false
      rescue Errno::EPERM
        false
      end

      # @param seconds [Numeric]
      # @yieldreturn [Boolean] done waiting
      # @return [void]
      def await(seconds)
        deadline = UI.monotonic + seconds
        sleep(POLL) until yield || UI.monotonic >= deadline
      end
    end
  end
end

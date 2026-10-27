# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module Execution
    # The side channel between a keypress and a running agent.
    #
    # `claude -p` takes no input once it starts, so the only way to reach an
    # agent mid-flight is a file it has been told to poll: each invocation gets
    # a control file of its own, named in its prompt, and a keypress writes a
    # word into every file currently registered. Like everything else about the
    # prompt this is a request — an agent deep in a tool call reads the file at
    # its next step, not instantly — which is why {#quit!} also arms a deadline
    # the {Executor} checks, so "quit" is eventually a guarantee too.
    module Control
      # What a keypress writes into a control file. One word, one line, so an
      # agent can act on `File.read(path).strip` and nothing subtler.
      WRAP_UP = "WRAP_UP"
      STOP = "STOP"

      # Ctrl-C: STOP, and the run will be started again, so the agent leaves
      # a resume note before it goes. The prompt says what that note is.
      INTERRUPT = "INTERRUPT"

      # The clock's warnings start with this; the agent's prompt explains them.
      WARN = "WARN"

      # From the page, to one agent: stop at the next safe point, read the
      # plan's mailbox, and wait there for the next message before going on.
      # A person holds an agent to say something to it.
      HOLD = "HOLD"

      # The words a person may send one agent from the page, by command kind.
      # There is no word for compacting: `/compact` is the caller's command,
      # not one an agent can run on itself, so the harness stops the agent and
      # compacts its session from outside (see {Executor::Handle#compact!}).
      WORDS = { "hold" => HOLD, "wrap_up" => WRAP_UP, "stop" => STOP }.freeze

      # Redis stopped answering (W32): every agent stops at its next safe
      # point and waits until the file says anything else. Its clock stands
      # still meanwhile, so the wait costs it no time.
      PAUSE = "PAUSE"

      # Redis is back: carry on from where the PAUSE found you.
      RESUME = "RESUME"

      # Seconds between {#quit!} and the harness terminating whatever is still
      # running. Long enough to write files and a handoff note; short enough
      # that q means quit rather than "quit eventually".
      GRACE = 60

      @mutex = Mutex.new
      @files = []
      @quit = false
      @interrupted = false
      @paused = false
      @deadline = nil

      class << self
        # Register a fresh control file for one invocation and hand back its
        # path, to be named in the agent's prompt.
        #
        # @param dir [String] where the file lives (the trace dir — outside the
        #   repository for the same reason traces are)
        # @param name [String] something findable: plan ordinal and agent name
        # @return [String]
        def register(dir, name)
          FileUtils.mkdir_p(dir)
          path = File.join(dir, "control-#{name}-#{Process.pid}-#{format("%04x", rand(0x10000))}")
          File.write(path, "")
          @mutex.synchronize { @files << path }
          path
        end

        # Take on the file an agent started by an earlier engine was told
        # about, so a stop or an INTERRUPT broadcast now reaches it too.
        #
        # @param path [String] the file named in the agent's prompt
        # @return [String] +path+
        def adopt(path)
          unless File.exist?(path)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, "")
          end
          @mutex.synchronize { @files << path unless @files.include?(path) }
          path
        end

        # Forget a finished invocation's file. The file itself is removed so a
        # crashed run does not leave stale STOPs for the next one to find.
        #
        # @param path [String]
        # @return [void]
        def release(path)
          @mutex.synchronize { @files.delete(path) }
          FileUtils.rm_f(path)
        end

        # One line into one file, from the clock. Not a broadcast: a warning is
        # about one agent's own deadline.
        #
        # @param path [String]
        # @param text [String]
        # @return [void]
        def write(path, text)
          File.write(path, text.empty? ? "" : "#{text}\n")
        rescue SystemCallError
          # The invocation finished and released its file; nothing to warn.
        end

        # `w`: every running agent is asked to finish the essential remainder
        # as fast as it can. The loop itself keeps going.
        #
        # @return [void]
        def wrap_up! = broadcast(WRAP_UP)

        # `n`: every running agent is asked to write out what it has and end
        # its turn. The loop keeps going — under chaining that is exactly what
        # hands the plan to the next agent.
        #
        # @return [void]
        def stop! = broadcast(STOP)

        # `q`: {#stop!}, plus the loop ends after this round, plus a deadline —
        # {GRACE} seconds from now — after which the {Executor} aborts whatever
        # is still running rather than waiting on its goodwill.
        #
        # @return [void]
        def quit!
          stop!
          @mutex.synchronize {
            # Quitting overrides a pause: the clocks run again, so an agent
            # that does not stop is still stopped.
            @paused = false
            @quit = true
            @deadline ||= UI.monotonic + GRACE
          }
        end

        # Ctrl-C, the first time: {#quit!}, except that every running agent is
        # told the run is being interrupted rather than stopped, so it writes
        # down where it got to. A restart then reads that note instead of
        # redoing, or half-redoing, the work.
        #
        # @return [void]
        def interrupt!
          broadcast(INTERRUPT)
          @mutex.synchronize {
            @quit = true
            @interrupted = true
            @deadline ||= UI.monotonic + GRACE
          }
        end

        # Every running agent waits where it is (W32).
        #
        # @return [void]
        def pause!
          @mutex.synchronize { @paused = true }
          broadcast(PAUSE)
        end

        # Every paused agent carries on.
        #
        # @return [void]
        def resume!
          @mutex.synchronize { @paused = false }
          broadcast(RESUME)
        end

        # @return [Boolean] whether agents are paused; their clocks stand still
        def paused? = @mutex.synchronize { @paused }

        # @return [Boolean] whether `q` has been pressed
        def quit? = @mutex.synchronize { @quit }

        # @return [Boolean] whether Ctrl-C has been pressed
        def interrupted? = @mutex.synchronize { @interrupted }

        # Ctrl-C: the graceful first press and the hard second.
        #
        # A trap handler may not take a mutex, so the first press hands
        # {#interrupt!} to a thread; the second raises, as Ctrl-C always has.
        #
        # @param signals [Array<String>] each handled as Ctrl-C is; `openlanes
        #   start` adds TERM, so a service manager's stop is as graceful
        # @yieldreturn [Object]
        # @return [Object] the block's value
        def on_interrupt(signals = %w[INT])
          previous = signals.to_h do |signal|
            [signal, Signal.trap(signal) do
              # A plain read, not {#interrupted?}: a trap handler may not lock.
              raise Interrupt if @interrupted || @pending_interrupt

              @pending_interrupt = true
              Thread.new { interrupt! }
            end]
          end
          yield
        ensure
          @pending_interrupt = false
          previous&.each { |signal, handler| Signal.trap(signal, handler || "DEFAULT") }
        end

        # @return [Boolean] whether the grace period after `q` has run out
        def overdue?
          @mutex.synchronize { !@deadline.nil? && UI.monotonic > @deadline }
        end

        # Back to rest, for the next `Runner#call` — and for the suite, where
        # one example's q must not quit every example after it.
        #
        # @return [void]
        def reset!
          @mutex.synchronize {
            @files.each { |f| FileUtils.rm_f(f) }
            @files.clear
            @quit = false
            @paused = false
            @interrupted = false
            @deadline = nil
          }
        end

        private

        # @param word [String]
        # @return [void]
        def broadcast(word)
          @mutex.synchronize { @files.dup }.each do |path|
            File.write(path, "#{word}\n")
          rescue SystemCallError
            # A file whose invocation just finished is not an error to miss.
          end
        end
      end
    end
  end
end

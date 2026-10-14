# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module Live
    class Copilot
      # c3po-operator itself (W17): the responder the API server hands
      # {Copilot}. Each message the person sends becomes one `claude -p`,
      # resumed from the conversation's session, so the agent remembers what
      # was said before; it answers in prose and `c3po` cards, which {Cards}
      # turns into the turns the page draws.
      #
      # It runs in the API server because that is where the conversation
      # already arrives and is stored: the server takes the message, answers
      # it, and writes the answer to the stream the page follows. It needs no
      # engine, so it also answers under `openlanes web` alone, after a run
      # has ended. The server calls it through {Copilot#answer} on its
      # background path ({Web::Context#background}), apart from the request,
      # and on that thread's own Redis connection; a failure that escapes
      # here is answered for by {Copilot#answer}. Messages are answered one
      # at a time, so two `claude` processes never resume one session at once.
      #
      # The boundary is the plan agents' boundary, narrowed. The tools are
      # fixed to {TOOLS} and the Bash commands to the agent's `allowed_tools`,
      # the read-only `openlanes` queries; {Execution::Executor#denied_for}
      # adds the network tools and every command that leaves the machine, and
      # {WRITE_TOOLS} goes on top. And it acts on nothing: a card is a
      # proposal, sent only when the person presses its button.
      class Operator
        # The agent's definition, in `agents/`.
        NAME = "c3po-operator"

        # The only built-in tools it has: reading files, and Bash for the
        # `openlanes` queries its definition allows.
        TOOLS = %w[Read Grep Glob Bash].freeze

        # Denied as well, should a CLI or a settings file offer them anyway:
        # it never edits code or plan documents (W17), and a sub-agent would
        # start with tools of its own.
        WRITE_TOOLS = %w[Edit Write MultiEdit NotebookEdit Task Agent].freeze

        # What `claude -p --resume` prints, on stderr, for a session it does not have.
        MISSING = /No conversation found with session ID/

        # Seconds an answer may take when the definition names none.
        TIMEOUT = 180

        # @param root [String] the checkout
        # @param plans_dir [String]
        # @param stores [#current] a store per thread; the answering thread
        #   takes its own, which the server's background path releases
        # @param keys [OpenLanes::Live::Keys]
        # @param agent [OpenLanes::Agents::Agent]
        # @param spawn [Proc] `argv, chdir:, env:` → {Execution::Child}; the suite's seam
        # @param trace_dir [String] where each answer's raw stream is kept, and
        #   where the agents' transcripts are read from
        def initialize(root:, plans_dir:, stores:, keys:, agent: Agents.find(NAME), spawn: Execution::Child.method(:spawn),
          trace_dir: Execution::Executor::TRACE_DIR)
          raise OpenLanes::Error, "no agent definition named #{NAME}" unless agent

          @root = File.expand_path(root)
          @plans_dir = plans_dir
          @stores = stores
          @keys = keys
          @agent = agent
          @spawn = spawn
          @trace_dir = trace_dir
          @mutex = Mutex.new
          @turns = Mutex.new
          @child = nil
          @stopped = false
        end

        # Answer one message, the responder's side of {Copilot#answer}: run
        # the agent, keep its session and what it spent, and turn what it
        # said into turns. A run that fails is answered as text saying why; a
        # message that waits while another is answered waits its turn.
        #
        # @param turn [OpenLanes::Live::Copilot::Turn] the person's
        # @return [Array<OpenLanes::Live::Copilot::Turn>]
        # @raise [OpenLanes::Error] when the server is stopping
        def call(turn) = @turns.synchronize { answer(turn) }

        # @param turn [OpenLanes::Live::Copilot::Turn]
        # @return [Array<OpenLanes::Live::Copilot::Turn>]
        def answer(turn)
          raise OpenLanes::Error, "the server is stopping" if @stopped

          board = Live.board(store:, keys: @keys)
          brief = Brief.new(text: turn.text, board: board[:me], others: board[:others], plans_dir: @plans_dir, trace_dir: @trace_dir)
          record = session
          run = invoke(brief.to_s, record["session"])
          # A session `claude` no longer has (its history was cleared, or the
          # conversation was started on another machine) fails at once; the
          # conversation starts again rather than staying broken.
          if stale?(run, record)
            store.hdel(@keys.copilot_session, "session")
            run = invoke(brief.to_s, nil)
          end
          usage = spend(run, record)
          return [failure(turn, run, usage)] unless run.ok

          Cards.turns(run.transcript.result, id: turn.id, usage:, board: board[:me])
        end

        # Stop answering: the message under way is cut short, and any still
        # waiting is answered with why. The server calls it on its way down.
        #
        # @return [void]
        def stop
          child = @mutex.synchronize do
            @stopped = true
            @child
          end
          child&.terminate(grace: 1, drain: 1)
        end

        # The argv one answer runs, exposed so a spec can check the boundary
        # without starting anything.
        #
        # @param prompt [String]
        # @param session [String, nil] the conversation to carry on
        # @return [Array<String>]
        def argv(prompt, session)
          profile.adapter.argv(
            Adapters::Invocation.new(prompt:,
              root:            @root,
              model:           profile.model,
              effort:          profile.effort,
              allowed_tools:   @agent.allowed_tools,
              denied_tools:    executor.denied_for(@agent) + WRITE_TOOLS,
              denied_commands: executor.denied_commands(@agent),
              network:         @agent.network,
              resume:          (session if profile.adapter.resumes?),
              dirs:            [@trace_dir],
              brief:           false,
              tools:           TOOLS,
              system:          @agent.prompt)
          )
        end

        # @return [OpenLanes::Agents::Profile]
        def profile = @profile ||= Agents::Profile.resolve(@agent)

        private

        # What one `claude -p` did.
        Run = Data.define(:ok, :transcript, :note)

        # @return [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore] this thread's
        def store = @stores.current

        # @param prompt [String]
        # @param session [String, nil]
        # @return [Run]
        def invoke(prompt, session)
          FileUtils.mkdir_p(@trace_dir)
          trace = File.join(@trace_dir,
            format("%s-copilot-%s-%d-%04x.ndjson",
              Time.now.strftime("%Y%m%d-%H%M%S"),
              NAME,
              Process.pid,
              rand(0x10000)))
          transcript = profile.adapter.transcript(trace:)
          child = @spawn.call(argv(prompt, session), chdir: @root, env: profile.adapter.environment)
          # {#stop} may have run while this was starting, and seen no child to end.
          stopping = @mutex.synchronize do
            @child = child
            @stopped
          end
          child.terminate(grace: 1, drain: 1) if stopping
          status = watched(child) { child.each_chunk { transcript.push(it) } }
          transcript.finish
          Run.new(ok: status.success? && !transcript.failed? && !@timed_out, transcript:, note: note(status, transcript, trace))
        ensure
          transcript&.finish
          @mutex.synchronize { @child = nil }
        end

        # Wait for the child, ending it once {#timeout} has passed. The
        # answer is advisory; a copilot that hangs must not hold the next
        # message for ever.
        #
        # @param child [OpenLanes::Execution::Child]
        # @return [Process::Status]
        def watched(child)
          @timed_out = false
          watchdog = Thread.new do
            sleep(timeout)
            @timed_out = true
            child.terminate
          end
          yield
          child.wait
        ensure
          watchdog&.kill
        end

        # @return [Boolean] whether `claude` said it has no such session, on one
        #   it was asked to resume; any other failure is reported, not retried
        def stale?(run, record)
          !run.ok && record["session"] && [run.transcript.error, *run.transcript.plain].any? { it.to_s.match?(MISSING) }
        end

        # @return [Integer] seconds
        def timeout = @agent.timeout || TIMEOUT

        # @return [String] why an answer failed, for the person
        def note(status, transcript, trace)
          return "it took longer than #{timeout} seconds" if @timed_out
          return "#{profile.adapter.executable} reported: #{transcript.error}" if transcript.failed?
          return "#{profile.adapter.executable} exited #{status.exitstatus}: #{transcript.plain.last(3).join(" ")}" unless status.success?

          "trace: #{trace}"
        end

        # The session, the model and the running total, kept in Redis
        # ({Keys#copilot_session}) so the next message, from this server or
        # one started after it, carries on the same conversation.
        #
        # @param run [Run]
        # @param record [Hash{String => String}]
        # @return [Hash] `{model, up, down}`
        def spend(run, record)
          usage = { model: model, up: record["up"].to_i + run.transcript.up, down: record["down"].to_i + run.transcript.down }
          key = @keys.copilot_session
          store.hset(key, "session", run.transcript.session) if run.transcript.session
          store.hset(key, "model", usage[:model].to_s)
          store.hset(key, "up", usage[:up])
          store.hset(key, "down", usage[:down])
          usage
        end

        # @return [Hash{String => String}]
        def session = store.hgetall(@keys.copilot_session)

        # The full id the header shows, as a car's does.
        #
        # @return [String, nil]
        def model = profile.adapter.model_entry(profile.model)&.id || profile.model

        # @return [OpenLanes::Live::Copilot::Turn]
        def failure(turn, run, usage)
          Turn.new(id: "#{turn.id}.1",
            from: "copilot",
            kind: "text",
            usage:,
            text: "c3po-operator could not answer: #{run.note}. Ask again, or look at the trace.")
        end

        # For its boundary only: who may run what, as plan agents are told.
        #
        # @return [OpenLanes::Execution::Executor]
        def executor = @executor ||= Execution::Executor.new(root: @root)
      end
    end
  end
end

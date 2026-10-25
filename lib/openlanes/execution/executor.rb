# frozen_string_literal: true

require "fileutils"
require "shellwords"
require "tmpdir"

module OpenLanes
  module Execution
    # Runs one agent against one plan by shelling out to a coding agent CLI:
    # `claude` unless the agent's definition or the plan's spec.md names
    # another {OpenLanes::Adapters adapter}.
    #
    # The autonomy boundary is "docs plus code, but nothing leaves the machine",
    # and it is enforced twice over:
    #
    #   BEFORE — the agent is told, and `--disallowedTools` withholds the tools
    #            that would let it push.
    #   AFTER  — {Boundary} checks that HEAD did not move and that no
    #            remote-tracking ref was moved by a push. A prompt is a request;
    #            a check is a guarantee, and only one of them survives a model
    #            deciding it knows better.
    class Executor
      # What one invocation did, and what it spent doing it.
      #
      # {#to_ary} is deliberate: every caller of {Executor#call} destructures
      # `ok, note = executor.call(...)`, and the meter is an addition to that
      # answer rather than a replacement for it. Callers that want the tokens
      # ask for them by name.
      #
      # @!attribute [r] ok
      #   @return [Boolean]
      # @!attribute [r] note
      #   @return [String] one line, for the report
      # @!attribute [r] up
      #   @return [Integer] tokens sent, sub-agents included
      # @!attribute [r] down
      #   @return [Integer] tokens generated
      # @!attribute [r] subagents
      #   @return [Integer] sub-agents this agent spawned
      # @!attribute [r] delegated
      #   @return [Integer] of {#up}, how much arrived as an unsplit sub-agent
      #     total rather than as a direction of its own
      # @!attribute [r] seconds
      #   @return [Float] wall clock, from argv to exit
      # @!attribute [r] killed
      #   @return [Symbol, nil] :timeout when the clock's backstop fired, :key
      #     when somebody pressed k, :budget when the token meter crossed the
      #     cap, :quit when the grace period after q ran out, nil otherwise
      # @!attribute [r] pid
      #   @return [Integer, nil]
      # @!attribute [r] cached
      #   @return [Integer] of {#up}, read back from the prompt cache
      # @return [Data]
      Result = Data.define(:ok, :note, :up, :down, :subagents, :delegated, :seconds, :killed, :pid, :cached) do
        def initialize(killed: nil, pid: nil, cached: 0, **rest) = super

        # @return [Integer] new input, cache writes and output
        def fresh = up - cached + down

        # @return [Array(Boolean, String)]
        def to_ary = [ok, note]
      end

      # A person's request to compact one running agent's session (W28),
      # and, once the harness has acted on it, how that went.
      # {Live::Commands} holds on to it and replies once {#finished?}.
      #
      # @!attribute [r] model
      #   @return [String, nil] the model the session carries on in; nil keeps
      #     the one it was started on
      # @!attribute [r] status
      #   @return [String, nil] "done" once the continuation has started,
      #     "refused" when it could not be, nil while under way
      # @!attribute [r] reason
      #   @return [String, nil]
      # @!attribute [r] restart
      #   @return [Boolean] whether the agent, stopped for a compaction that
      #     could not happen, gets its round back to start again afresh
      Compaction = Struct.new(:model, :status, :reason, :restart) do
        # @return [Boolean]
        def finished? = !status.nil?

        # @param reason [String]
        # @return [void]
        def done!(reason) = settle("done", reason)

        # @param reason [String]
        # @param restart [Boolean] the agent stopped for nothing, and is
        #   started again from its resume note in a fresh session
        # @return [void]
        def refuse!(reason, restart: false)
          self.restart = restart
          settle("refused", restart ? "#{reason}; it restarts from its resume note in a fresh session" : reason)
        end

        private

        # The reason is set before the status, so a reader on another thread
        # that sees it finished also sees why.
        #
        # @return [void]
        def settle(status, reason)
          self.reason = reason
          self.status = status
        end
      end

      # What the dispatcher holds on a running invocation, so a keypress can
      # reach it: the process, its clock and its control file.
      #
      # Filled in by {#call} once the child exists. Every method tolerates the
      # gap before that, because the keyboard does not wait.
      class Handle
        def initialize
          @mutex = Mutex.new
          @requested = nil
          @compaction = nil
          @closed = false
        end

        # @return [OpenLanes::Execution::Child, nil] the process running now,
        #   which after a compaction is no longer the first one
        attr_accessor :child

        # @return [String, nil] the CLI's session id, once its stream named it
        attr_accessor :session

        # @return [String, nil] the raw NDJSON trace the agent's stream is
        #   copied into, so the engine journal can name it and its offset
        attr_accessor :trace

        # @return [OpenLanes::Execution::Executor::Compaction, nil] the latest
        #   compaction asked for
        def compaction = @mutex.synchronize { @compaction }

        # @return [OpenLanes::Execution::Clock, nil]
        attr_reader :clock

        # The clock, once {Executor#call} has started it. Seconds granted
        # before then (a round given more time, E1) go onto it now rather
        # than being dropped for want of a clock.
        #
        # @param clock [OpenLanes::Execution::Clock, nil]
        # @return [void]
        def clock=(clock)
          @mutex.synchronize do
            @clock = clock
            clock&.extend!(@pending) if @pending&.positive?
            @pending = nil
          end
        end

        # @return [String, nil]
        attr_reader :control

        # The control file, once {Executor#call} has registered it. A stop
        # asked for before then is written the moment it exists, so an agent
        # still starting up when Stop All came is not left running.
        #
        # @param path [String, nil]
        # @return [void]
        def control=(path)
          @mutex.synchronize do
            @control = path
            Control.write(path, Control::STOP) if path && @stop_requested
          end
        end

        # Stop at the next step, now or as soon as there is a control file.
        #
        # @return [void]
        def request_stop!
          @mutex.synchronize do
            @stop_requested = true
            Control.write(@control, Control::STOP) if @control
          end
        end

        # @return [Symbol, nil] why the process was killed, once it was
        attr_reader :killed

        # @return [Integer, nil]
        def pid = child&.pid

        # @return [Integer, nil]
        def remaining = clock&.remaining

        # @return [Symbol, nil]
        def phase = clock&.phase

        # STOP, a grace period, then {Child#terminate}: TERM and KILL to the
        # agent's whole process group, and its pipe closed, so the invocation
        # ends even when a tool the agent started is what hangs. The grace is
        # what lets an agent mid-write finish the line.
        #
        # @param grace [Integer] seconds
        # @param reason [Symbol] :key, :timeout, :budget or :quit
        # @return [void]
        def kill!(grace: 15, reason: :key)
          @killed ||= reason
          Control.write(control, Control::STOP) if control
          sleep(grace) if grace.positive?
          child&.terminate
        end

        # More time on the clock, or on the clock to come.
        #
        # @param seconds [Integer]
        # @return [Boolean] false when the clock had already stopped the agent
        def extend!(seconds)
          @mutex.synchronize do
            next @clock.extend!(seconds) if @clock

            @pending = @pending.to_i + seconds
            true
          end
        end

        # Ask for the session to be compacted (W28): INTERRUPT, so the agent
        # leaves a resume note and ends its turn, and SIGKILL after +grace+
        # seconds if it has not. {Executor#call} then compacts the session and
        # carries it on. Asked twice while under way, it is the same request.
        #
        # @param model [String, nil] what the session carries on in
        # @param grace [Integer] seconds before the agent is made to stop
        # @return [OpenLanes::Execution::Executor::Compaction]
        def compact!(model: nil, grace: Control::GRACE)
          process = nil
          @mutex.synchronize do
            return @compaction if @compaction && !@compaction.finished?

            @compaction = Compaction.new(model:)
            if @closed
              @compaction.refuse!("the agent finished before it could be compacted")
              return @compaction
            end
            # Aimed at the process running now, before the request is visible:
            # once it is, {Executor#call} may already be compacting, and an
            # INTERRUPT or a kill sent after that would stop the resumed session.
            process = child
            Control.write(control, Control::INTERRUPT) if control
            @requested = @compaction
          end
          stop_after(grace, process)
          @compaction
        end

        # @return [OpenLanes::Execution::Executor::Compaction, nil] the request
        #   to act on now, handed out once
        def take_compaction = @mutex.synchronize { @requested.tap { @requested = nil } }

        # The invocation is over: a request that arrives now, or one that came
        # too late to be acted on, is refused rather than left waiting.
        #
        # @return [void]
        def close!
          @mutex.synchronize do
            @closed = true
            @requested&.refuse!("the agent finished before it could be compacted")
            @requested = nil
          end
        end

        private

        # @param grace [Integer]
        # @param process [OpenLanes::Execution::Child, nil] the one asked to stop
        # @return [void]
        def stop_after(grace, process)
          return unless process

          Thread.new do
            sleep(grace) if grace.positive?
            process.terminate if process.equal?(child)
          end
        end
      end

      # The transcripts of one invocation's sessions, added up: the agent's own
      # and, once compacted, the `/compact` and the continuation after it. One
      # car on the board, so one meter, which must not drop when the second
      # session starts counting from zero.
      class Sessions
        def initialize = @all = []

        # @param transcript [OpenLanes::Execution::Transcript]
        # @return [OpenLanes::Execution::Executor::Sessions]
        def <<(transcript)
          @all << transcript
          self
        end

        # @return [OpenLanes::Execution::Transcript] the session running now
        def current = @all.last

        # @return [OpenLanes::Execution::Transcript, nil] the one before it
        def previous = @all[-2]

        # @return [Integer]
        def up = @all.sum(&:up)

        # @return [Integer]
        def down = @all.sum(&:down)

        # @return [Integer]
        def cached = @all.sum(&:cached)

        # @return [Integer]
        def fresh = up - cached + down

        # @return [Integer]
        def spawned = @all.sum(&:spawned)

        # @return [Integer]
        def delegated = @all.sum(&:delegated)

        # @return [Integer]
        def tools = @all.sum(&:tools)

        # What the sessions already over spent, added to the running one's
        # progress so the meter carries on rather than starting again. Their
        # journal lines go first, for the same reason: the dispatcher counts
        # its place in the list, and a list that started again at the
        # continuation would have it skip the continuation's first entries.
        # `running` is left as the live session reports it: a session that is
        # over has no sub-agent still in flight.
        #
        # @param progress [OpenLanes::Execution::Transcript::Progress]
        # @return [OpenLanes::Execution::Transcript::Progress]
        def carry(progress)
          before = @all[0...-1]
          progress.with(up: progress.up + before.sum(&:up),
            down: progress.down + before.sum(&:down),
            subagents: progress.subagents + before.sum(&:spawned),
            journal: (before.flat_map { it.respond_to?(:journal) ? it.journal : [] } + progress.journal).freeze)
        end
      end

      # Tools no agent may use under this autonomy level, whatever its definition
      # asks for. Git itself is reachable through Bash, which is why the
      # after-check exists as well.
      #
      # The exception is an agent that declares `network: true`. Closed is the
      # right default — most specialists here read the repository and write to
      # it, and a model that decides to go looking online mid-task is a model
      # doing something nobody asked for. But a researcher inverts that: reading
      # the internet is the entire job, and denying it silently produced an
      # agent that ran, found nothing, and reported success.
      DENIED_TOOLS = %w[WebFetch WebSearch].freeze

      # The whole tool set of a {Agents::Agent#confined? confined} agent.
      # `--tools` takes every other tool away and `dontAsk` refuses whatever
      # the allow list below does not name, so Edit reaches only its files
      # and Bash only these commands: a prompt that says "only spec.md" is a
      # request, this is the check.
      CONFINED_TOOLS = %w[Read Grep Glob Edit Bash].freeze

      # The commands a confined agent may run besides this checkout's own
      # `openlanes state`, which signs its ledger. A grant is `Bash(cmd:*)`,
      # so every flag of a listed command is reachable: `rg --pre` runs any
      # program and `git log|show|diff --output=` writes any file, which is
      # how the first version of this list escaped its own confinement. Only
      # commands with no flag that executes or writes belong here; Read, Grep
      # and Glob cover the rest.
      CONFINED_COMMANDS = ["ls", "git status"].freeze

      # The one `openlanes` subcommand a confined agent may run: `state`
      # shows and signs its ledger. The whole executable would hand it
      # `run` and `resync`, which rename folders.
      CONFINED_CLI = "#{Prompt::EXECUTABLE} state".freeze

      # Commands that leave the machine, denied to every agent by default.
      #
      # These are passed to `claude` as `Bash(<command>:*)` tool specifiers, so
      # they are withheld rather than merely discouraged. This list spent a while
      # as a regular expression that nothing referenced — a guard in the shape of
      # a constant, enforcing nothing — which is exactly how `gh pr review` came
      # to be reachable by an agent nobody had granted it to.
      #
      # `git rebase` is here because the harness owns the rebase onto the
      # default branch ({Vcs::Refresh}): an agent resolving a stopped one only
      # edits and stages, and a `--continue`, `--skip` or `--abort` of its own
      # would move HEAD inside the window the after-check guards.
      FORBIDDEN_COMMANDS = [
        "git push", "git commit", "git rebase",
        "gh pr create", "gh pr edit", "gh pr merge",
        "gh pr review", "gh pr comment",
        "gh release create"
      ].freeze

      # The subset no agent's `may:` can lift, however its definition is written.
      #
      # Pushing and merging change a branch everybody else builds on, and an
      # unattended loop doing either has no way to be wrong quietly. Reviewing
      # does not: an approval is reversible, visible, and attributable to the
      # identity that made it. That difference is the whole line between
      # `hansolo-reviewer` approving and `hansolo-reviewer` merging.
      #
      # A rebase is the harness's alone for the same reason a merge is: it
      # rewrites the branch a pull request is built from, and the harness
      # pushes that rewrite with a lease only it can check.
      UNGRANTABLE = ["git push", "gh pr merge", "git rebase"].freeze

      # How much of what the agent said survives into a one-line report.
      REASON_LIMIT = 300

      # Seconds an agent gets when neither its frontmatter nor `--timeout` says.
      DEFAULT_TIMEOUT = 900

      # Where the raw stream of each invocation is kept.
      #
      # Under `run -j` several agents work at once, and more than one
      # `openlanes` may be driving the same checkout, so a trace is named
      # per invocation rather than shared. To get an agent's final answer back
      # out of one afterwards:
      #
      #   jq -r 'select(.type=="result").result' <trace>
      #
      # and to replay what it did, tool call by tool call:
      #
      #   jq -r 'select(.type=="assistant")
      #          | .message.content[]?
      #          | select(.type=="tool_use")
      #          | "\(.name) \(.input|tostring[0:80])"' <trace>
      #
      # Outside the repository on purpose: the harness checks afterwards that the
      # agent moved nothing it should not have, and a megabyte of NDJSON dropped
      # into the working tree is exactly the kind of thing that check would then
      # have to learn to ignore.
      TRACE_DIR = File.join(Dir.tmpdir, "openlanes-traces")

      # Environment variables the `claude` CLI reads as credentials, in
      # preference to a claude.ai login.
      #
      # A project `.env` that sets one of these for the application's own use
      # reaches every agent a run spawns. `claude` then authenticates with that
      # key rather than the login, and a stale or unrelated one turns an entire
      # run into `401 API key is invalid`, three minutes per agent. The CLI warns
      # rather than unsets. Driving it with an API key on purpose is legitimate,
      # and nothing here can tell the two apart.
      CREDENTIAL_VARS = %w[ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN].freeze

      # What `claude -p --resume <id>` prints for an id it has no session for,
      # in the directory it was run from (2.1.x): this line on stderr, then a
      # `result` event with `is_error`, zero turns and zero tokens, exit 1.
      SESSION_MISSING = /No conversation found with session ID/

      # @param env [Hash]
      # @return [Array<String>] credential variables currently set
      def self.foreign_credentials(env = ENV)
        CREDENTIAL_VARS.reject { |name| env[name].to_s.strip.empty? }
      end

      # @param root [String] the repository the agents work in
      # @param spawn [Proc] `argv, chdir:, env:` → {OpenLanes::Execution::Child}, swappable so the
      #   suite can play back a fake process without spawning one
      # @param timeout [Integer, nil] `--timeout`: a cap on every agent's clock,
      #   or nil to let each agent's own frontmatter clock stand
      # @param dry_run [Boolean] plan the invocation, do not run it
      # @param trace_dir [String] where each invocation's raw stream is kept
      # @param instructions [String, nil] what `run --prompt` typed, appended
      #   to the agent's own prompt. The command only accepts it alongside
      #   `--agent`, so exactly one agent ever hears it.
      # @param model [String, nil] what `run --model` typed. The flag actually
      #   typed beats what an agent's frontmatter declares, the same precedence
      #   every other flag here follows; nil leaves each agent its own choice.
      # @param max_tokens [Integer, nil] budget per invocation, input plus
      #   output, sub-agents included. The prompt states it so the agent can
      #   plan to finish inside it, and the meter enforces it so the statement
      #   is true. nil is unmetered.
      # @param fresh_budget [Boolean] count only new tokens against
      #   +max_tokens+, leaving out cache reads; what `eval --live` uses
      # @param lean [Boolean] start agents without the operator's personal
      #   plugins, skills, hooks and MCP servers; `run --user-config` turns it off
      def initialize(root:, spawn: Child.method(:spawn), timeout: nil, dry_run: false,
        trace_dir: TRACE_DIR, instructions: nil, model: nil, max_tokens: nil, lean: true,
        fresh_budget: false)
        @root = File.expand_path(root)
        @spawn = spawn
        @timeout = timeout
        @dry_run = dry_run
        @trace_dir = trace_dir
        @instructions = instructions.to_s.strip
        @model = model
        @max_tokens = max_tokens
        @lean = lean
        @fresh_budget = fresh_budget
        @preferred = {}
      end

      # @return [String]
      attr_reader :root

      # @return [String, nil] what `run --model` typed
      attr_reader :model

      # Which CLI, model and effort this agent gets on this plan.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject, nil]
      # @return [OpenLanes::Agents::Profile]
      def profile_for(agent, subject = nil)
        spec = subject ? Plans::Spec.for(subject) : nil
        Agents::Profile.resolve(agent, spec:, model: preferred_model(agent, subject) || @model)
      end

      # A model a person chose for one agent on one plan while the run was
      # going (W24), taken from that agent's next invocation. It beats
      # `run --model` because it was said later, about this agent in
      # particular. nil forgets the choice.
      #
      # @param ordinal [#to_s]
      # @param agent [String] the agent's name
      # @param model [String, nil]
      # @return [void]
      def prefer_model(ordinal, agent, model)
        key = [ordinal.to_s, agent.to_s]
        model.nil? ? @preferred.delete(key) : @preferred[key] = model.to_s
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject, nil]
      # @return [String, nil]
      def preferred_model(agent, subject)
        subject && @preferred[[subject.feature.ordinal.to_s, agent.name]]
      end

      # The clock this agent runs against: the tighter of its own frontmatter
      # and `--timeout`. A flag that could only loosen was useless the day
      # somebody wanted a quick run.
      #
      # {DEFAULT_TIMEOUT} steps in only when neither names a figure. It used
      # to be the flag's default instead, which silently cut every 1200-second
      # agent to 900 on the runs where nobody had typed `--timeout` at all.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @return [Integer]
      def timeout_for(agent) = [agent.timeout, @timeout].compact.min || DEFAULT_TIMEOUT

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @param root [String] the checkout the agent works in
      # @param round [Integer] which attempt on this plan this is
      # @param successor [String, nil] who the agent names on its `next:` line
      # @param handle [OpenLanes::Execution::Executor::Handle, nil] filled in for the caller
      # @param partners [Array<OpenLanes::Agents::Agent>] the other agents working this
      #   plan right now, named in the prompt beside the plan's mailbox
      # @param rebase [OpenLanes::Vcs::Refresh::Outcome, nil] a rebase stopped
      #   on conflicts: the invocation resolves it and does no plan work
      # @param resume [String, nil] the previous round's session id (M1), to
      #   carry on with this round's prompt; ignored by a CLI that cannot
      #   resume, and dropped for a fresh start when the CLI cannot find it
      # @return [OpenLanes::Execution::Executor::Result]
      # @yieldparam progress [OpenLanes::Execution::Transcript::Progress]
      def call(agent, subject, root: @root, round: 1, successor: nil, handle: nil, partners: [], rebase: nil,
        resume: nil, &on_progress)
        started = UI.monotonic
        if @dry_run
          return Result.new(ok: true,
            note: "dry run - would invoke #{agent.name}",
            up: 0,
            down: 0,
            subagents: 0,
            delegated: 0,
            seconds: 0.0)
        end

        profile = profile_for(agent, subject)
        if agent.confined? && !profile.adapter.enforces_tool_denial?
          return Result.new(ok: false,
            note: "#{agent.name} is confined to #{agent.confined_to.join(", ")}, and #{profile.adapter.executable} cannot enforce that",
            up: 0,
            down: 0,
            subagents: 0,
            delegated: 0,
            seconds: 0.0)
        end

        handle ||= Handle.new
        before = Boundary.snapshot(root)
        trace = trace_path(agent, subject)
        handle.trace = trace
        control = Control.register(@trace_dir, "#{subject.feature.ordinal}-#{agent.name}")
        handle.control = control
        resume = nil unless profile.adapter.resumes?
        argv = invocation(agent, subject, root:, control:, round:, successor:, partners:, rebase:, resume:)
        sessions = Sessions.new
        child = launch(argv, root:, profile:, trace:, handle:, sessions:, &on_progress)
        clock = Clock.new(seconds: timeout_for(agent),
          control:,
          on_expire: -> { handle.kill!(grace: 0, reason: :timeout) })
        handle.clock = clock
        clock.start

        begin
          status = drain(child, sessions, handle)
          if resume && !handle.killed && (lost = lost_session(status, sessions.current))
            UI.log("session #{resume} #{lost}, starting #{agent.name} fresh",
              level: :warn,
              plan:  subject.feature.ordinal.to_s,
              agent: agent.name)
            handle.session = nil
            argv = invocation(agent, subject, root:, control:, round:, successor:, partners:, rebase:)
            status = drain(launch(argv, root:, profile:, trace:, handle:, sessions:, &on_progress), sessions, handle)
          end
          while (compaction = handle.take_compaction)
            resumed = settling(compaction, agent) do
              carry_on(compaction, agent, subject, root:, profile:, trace:, handle:, sessions:, &on_progress)
            end
            status = resumed if resumed
          end
        ensure
          handle.close!
          clock.stop
          Control.release(control)
        end
        transcript = sessions.current

        if handle.killed
          return spent(sessions,
            started,
            ok:     false,
            pid:    handle.pid,
            killed: handle.killed,
            note:   "#{killed_note(handle.killed, clock)}, last seen #{transcript.activity || "starting up"} - trace: #{trace}")
        end
        unless status.success?
          return failure(sessions,
            started,
            "#{profile.adapter.executable} exited #{status.exitstatus}: #{said(transcript)} - trace: #{trace}",
            pid: handle.pid)
        end
        if transcript.failed?
          return failure(sessions,
            started,
            "#{profile.adapter.executable} reported: #{transcript.error} - trace: #{trace}",
            pid: handle.pid)
        end

        violation = before.violation(root)
        return failure(sessions, started, violation, pid: handle.pid) if violation

        spent(sessions,
          started,
          ok:   true,
          pid:  handle.pid,
          note: "completed#{" - #{sessions.tools} tool calls" if sessions.tools.positive?}")
      end

      # A failed invocation still spent what it spent, and a run that burned two
      # hundred thousand tokens before timing out is a different fact from one
      # that failed to authenticate and spent nothing. Both used to report the
      # same thing.
      #
      # @return [OpenLanes::Execution::Executor::Result]
      def failure(transcript, started, note, pid: nil) = spent(transcript, started, ok: false, note:, pid:)

      # @return [OpenLanes::Execution::Executor::Result]
      def spent(transcript, started, ok:, note:, pid: nil, killed: nil)
        Result.new(ok:,
          note:,
          up: transcript.up,
          down: transcript.down,
          subagents: transcript.spawned,
          delegated: transcript.delegated,
          seconds: UI.monotonic - started,
          killed:,
          pid:,
          cached: transcript.cached)
      end

      # @param transcript [OpenLanes::Execution::Transcript]
      # @return [String] the last few plain lines, clipped
      def said(transcript)
        text = (transcript.failed? ? transcript.error : transcript.plain.last(3).join(" ")).to_s.strip
        return "said nothing" if text.empty?

        text.length > REASON_LIMIT ? "#{text[0, REASON_LIMIT - 1]}..." : text
      end

      # @param reason [Symbol]
      # @param clock [OpenLanes::Execution::Clock]
      # @return [String]
      def killed_note(reason, _clock)
        case reason
        when :timeout then "timed out (killed #{Clock::GRACE}s after STOP)"
        when :budget then "token budget of #{@max_tokens} exceeded"
        when :quit then "still running after #{Control.interrupted? ? "ctrl-c" : "q"}, killed once the grace period ran out"
        else "killed by request"
        end
      end

      # The exact argv, exposed so a spec can assert the boundary flags without
      # running anything.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @param round [Integer] which attempt on this plan this is
      # @param successor [String, nil] who the agent names on its `next:` line
      # @param partners [Array<OpenLanes::Agents::Agent>]
      # @param rebase [OpenLanes::Vcs::Refresh::Outcome, nil]
      # @param resume [String, nil] a session id to carry on
      # @return [Array<String>]
      def invocation(agent, subject, root: @root, control: nil, round: 1, successor: nil, partners: [], rebase: nil,
        resume: nil)
        profile = profile_for(agent, subject)
        profile.adapter.argv(
          Adapters::Invocation.new(
            prompt:          prompt_for(agent, subject, root, control:, round:, successor:, partners:, profile:, rebase:),
            root:,
            model:           profile.model,
            effort:          profile.effort,
            allowed_tools:   allowed_for(agent, subject),
            denied_tools:    denied_for(agent),
            denied_commands: denied_commands(agent),
            network:         agent.network,
            lean:            @lean,
            resume:,
            tools:           (CONFINED_TOOLS if agent.confined?)
          )
        )
      end

      # What this particular agent may not touch: the network tools unless it
      # asked for them, plus every forbidden command it has not been granted.
      # Both decisions are recorded in a reviewable file rather than passed as a
      # flag by whoever happened to start the run.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @return [Array<String>]
      def denied_for(agent)
        tools = agent.network ? [] : DENIED_TOOLS
        tools + denied_commands(agent).map { |command| "Bash(#{command}:*)" }
      end

      # What this agent may use on this plan: its own `allowed_tools`, or for
      # a confined agent Edit on its files and nothing else that writes. The
      # leading `/` makes the rule absolute (`//Users/...`); one slash alone
      # is read relative to the settings file.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<String>]
      def allowed_for(agent, subject)
        return agent.allowed_tools unless agent.confined?

        edits = agent.confined_to.map { "Edit(/#{File.expand_path(it, subject.feature.path)})" }
        commands = [CONFINED_CLI, *CONFINED_COMMANDS].map { "Bash(#{it}:*)" }
        %w[Read Grep Glob] + edits + commands
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @return [Array<String>] commands withheld from this agent
      def denied_commands(agent) = FORBIDDEN_COMMANDS - granted_to(agent)

      # @param agent [OpenLanes::Agents::Agent]
      # @return [Array<String>] what its `may:` actually buys it
      def granted_to(agent) = agent.may - UNGRANTABLE

      private

      # Start one session's process and the transcript that reads it. Every
      # session of an invocation shares its trace file, which is opened for
      # appending, so a compacted run reads back as one stream.
      #
      # @return [OpenLanes::Execution::Child]
      def launch(argv, root:, profile:, trace:, handle:, sessions:, &on_progress)
        transcript = profile.adapter.transcript(trace:) do |progress|
          handle.session ||= progress.session
          on_progress&.call(sessions.carry(progress))
        end
        sessions << transcript
        child = @spawn.call(argv, chdir: root, env: profile.adapter.environment)
        handle.child = child
        transcript.pid = child.pid
        child
      end

      # Whether a resumed invocation failed because its session is gone,
      # rather than at anything it did, and what to say about it. The message
      # is the sure sign; a failure that spent nothing and called no tool is
      # taken as the same thing, because a CLI that rewords the message must
      # still not cost the round. Starting such a failure again fresh costs
      # one more start-up at worst: an invocation that spent nothing has
      # nothing to lose.
      #
      # That second case also catches an overload, an auth error or a network
      # drop at start-up, which the fresh start will usually hit again. The
      # line the CLI printed goes into the log beside the retry, so an outage
      # reads as an outage rather than as a lost session.
      #
      # @param status [Process::Status]
      # @param transcript [OpenLanes::Execution::Transcript]
      # @return [String, nil] why the session counts as lost, nil when it does not
      def lost_session(status, transcript)
        return nil if status.success? && !transcript.failed?

        said = [transcript.error, *transcript.plain].map(&:to_s).reject(&:empty?)
        return "not found" if said.any? { SESSION_MISSING.match?(it) }
        return nil unless transcript.up.zero? && transcript.down.zero? && transcript.tools.zero?

        detail = said.empty? ? "exit #{status.exitstatus}" : said.last.lines.first.strip[0, 200]
        "failed before spending anything (#{detail})"
      end

      # @return [Process::Status]
      def drain(child, sessions, handle)
        child.each_chunk do |out|
          sessions.current.push(out)
          abort_if_over(sessions, handle)
        end
        status = child.wait
        sessions.current.finish
        status
      end

      # The agent has stopped for its compaction (W28): its session is
      # compacted, then resumed with {Prompt#continuation}, on the model the
      # request names or the one it was on, under the same handle. The
      # request is answered once the continuation has started, which is the
      # moment a person can see it carry on.
      #
      # @param compaction [OpenLanes::Execution::Executor::Compaction]
      # @return [Process::Status, nil] how the continuation ended; nil when
      #   there was none, and the agent's own stop stands
      def carry_on(compaction, agent, subject, root:, profile:, trace:, handle:, sessions:, &)
        model = compaction.model || profile.model
        if handle.killed
          compaction.refuse!("#{agent.name} was stopped first (#{handle.killed})")
          return nil
        end
        unless (why = uncompactable(handle, profile))
          compacted = compact(agent, model, subject:, root:, profile:, trace:, handle:, sessions:)
          why = compacted unless compacted == true
        end
        if why
          compaction.refuse!("could not compact #{agent.name}: #{why}", restart: !handle.killed)
          return nil
        end

        Control.write(handle.control, "")
        prompt = Prompt.new(agent:, subject:, root:, profile:, control: handle.control).continuation
        child = launch(resumption(agent, profile, subject:, root:, session: handle.session, prompt:, model:),
          root:, profile:, trace:, handle:, sessions:,
          &)
        compaction.done!(compacted_note(agent, sessions, model, compaction))
        drain(child, sessions, handle)
      end

      # A compaction whose `/compact` or continuation could not even be
      # started is refused before the error goes on up, so the person who
      # asked is answered rather than left waiting on a thread that died.
      #
      # @param compaction [OpenLanes::Execution::Executor::Compaction]
      # @return [Process::Status, nil] what the block returned
      def settling(compaction, agent)
        yield
      rescue StandardError => e
        compaction.refuse!("could not compact #{agent.name}: #{e.message}") unless compaction.finished?
        raise
      end

      # @return [String, nil] why the session cannot be compacted, if it cannot
      def uncompactable(handle, profile)
        return "#{profile.adapter.name} cannot resume a session" unless profile.adapter.compacts?

        "no session id to resume" unless handle.session
      end

      # `/compact` sent into the stopped session.
      #
      # @return [true, String] true, or why it failed
      def compact(agent, model, subject:, root:, profile:, trace:, handle:, sessions:)
        argv = resumption(agent,
          profile,
          subject:,
          root:,
          session: handle.session,
          prompt: profile.adapter.compact_prompt,
          model:,
          slash_commands: true)
        status = drain(launch(argv, root:, profile:, trace:, handle:, sessions:), sessions, handle)
        transcript = sessions.current
        return "the agent was stopped during /compact (#{handle.killed})" if handle.killed
        return "/compact exited #{status.exitstatus}: #{said(transcript)}" unless status.success?
        return "/compact reported: #{transcript.error}" if transcript.failed?
        return "/compact did not compact: #{said(transcript)}" unless transcript.compacted

        true
      end

      # @return [String] the reply a person reads
      def compacted_note(agent, sessions, model, compaction)
        sizes = sessions.previous.compacted.values_at("pre_tokens", "post_tokens")
        tokens = sizes.all? ? " from #{sizes.first} to #{sizes.last} tokens" : ""
        "#{agent.name} compacted#{tokens} and carries on#{" on #{model}" if compaction.model}"
      end

      # The argv that carries an existing session on, with the boundary flags
      # every invocation gets, confined as the first invocation was.
      #
      # @return [Array<String>]
      def resumption(agent, profile, subject:, root:, session:, prompt:, model:, slash_commands: false)
        profile.adapter.argv(
          Adapters::Invocation.new(prompt:,
            root:,
            model:,
            effort:          profile.effort,
            allowed_tools:   allowed_for(agent, subject),
            denied_tools:    denied_for(agent),
            denied_commands: denied_commands(agent),
            network:         agent.network,
            lean:            @lean,
            resume:          session,
            slash_commands:,
            tools:           (CONFINED_TOOLS if agent.confined?))
        )
      end

      # One file per invocation. The plan number and the agent's name make it
      # findable; the pid and the clock keep two concurrent runs from writing to
      # the same one. See {TRACE_DIR} for how to read one back.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def trace_path(agent, subject)
        FileUtils.mkdir_p(@trace_dir)
        name = format("%s-%s-%s-%d-%04x.ndjson",
          Time.now.strftime("%Y%m%d-%H%M%S"),
          subject.feature.ordinal,
          agent.name,
          Process.pid,
          rand(0x10000))
        File.join(@trace_dir, name)
      end

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @param round [Integer]
      # @param successor [String, nil]
      # @param partners [Array<OpenLanes::Agents::Agent>]
      # @param rebase [OpenLanes::Vcs::Refresh::Outcome, nil]
      # @return [String]
      def prompt_for(agent, subject, root = @root, control: nil, round: 1, successor: nil, partners: [],
        profile: profile_for(agent, subject), rebase: nil)
        Prompt.new(agent:,
          rebase:,
          subject:,
          root:,
          profile:,
          round:,
          successor:,
          partners:,
          control:,
          instructions: @instructions,
          max_tokens:   @max_tokens,
          fresh_budget: @fresh_budget,
          seconds:      timeout_for(agent),
          denied:       denied_commands(agent),
          granted:      granted_to(agent)).to_s
      end

      # The token budget crossed, or the grace period after `q` spent. Both go
      # through the handle so the kill is the same kill a keypress makes.
      #
      # @param transcript [OpenLanes::Execution::Executor::Sessions]
      # @param handle [OpenLanes::Execution::Executor::Handle]
      # @return [void]
      def abort_if_over(transcript, handle)
        spent = @fresh_budget ? transcript.fresh : transcript.up + transcript.down
        if @max_tokens&.positive? && spent > @max_tokens
          handle.kill!(grace: 0, reason: :budget)
        elsif Control.overdue?
          handle.kill!(grace: 0, reason: :quit)
        end
      end
    end
  end
end

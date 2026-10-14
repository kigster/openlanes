# frozen_string_literal: true

module OpenLanes
  module Apps
    # Runs one plan's app (plan 012, B4): every process in `app:` started in
    # declared order, each on a port from {Ports}, the next only once the
    # previous is ready, and all of them stopped together.
    #
    # Every process is told every port (`PORT_API`, `PORT_WEB`) before the
    # first one starts, so a web process can find its API. Ports are
    # reserved up front for the same reason.
    #
    # A process runs as `sh -c <start>` through {Execution::Child}, which
    # leads a process group of its own: a dev server's watcher and workers
    # are grandchildren, and only a group stop reaches them. `Child` also
    # kills every group still running when this Ruby exits, which is what
    # stops the app when its runner does.
    #
    # Each transition is handed to +publisher+ as a {Status}; the runner
    # writes it to Redis for the Preview tab, and plan 014 reads the same
    # {#statuses} for its report.
    class Supervisor
      # The app did not come up. The message is the reason, for a person;
      # everything that had started has been stopped by the time it is raised.
      class StartFailed < Error; end

      # Seconds a process has to become ready (spec open question 10).
      READY_TIMEOUT = 30

      # Seconds between readiness probes.
      POLL = 0.1

      # Lines of a process's output kept, for the reason when it fails.
      TAIL = 20

      # What a process says when another took its port between the probe
      # and the bind: the one failure worth a second attempt.
      RACE = /EADDRINUSE|address already in use/i

      # One process the supervisor started.
      Running = Struct.new(:spec, :child, :waiter, :reader, :tail)

      # @param definition [OpenLanes::Apps::Definition]
      # @param root [String] the checkout every process runs in
      # @param plan [String] the ordinal
      # @param branch [String]
      # @param registry [OpenLanes::Apps::Ports]
      # @param publisher [#call, nil] given each {Status} as it happens
      # @param probe [#ready?]
      # @param framing [#check]
      # @param origin [String] the control room's origin, for {Framing}
      # @param ready_timeout [Numeric] seconds
      # @param poll [Numeric] seconds between probes
      # @param output [#call, nil] given a process's name and each line it prints
      def initialize(definition:, root:, plan:, branch:, registry: Ports.new, publisher: nil, probe: Probe, framing: Framing,
        origin: Framing::ORIGIN, ready_timeout: READY_TIMEOUT, poll: POLL, output: nil)
        @definition = definition
        @root = root
        @plan = plan
        @branch = branch
        @registry = registry
        @publisher = publisher
        @probe = probe
        @framing = framing
        @origin = origin
        @ready_timeout = ready_timeout
        @poll = poll
        @output = output
        @running = {}
        @ports = {}
        @statuses = {}
        @mutex = Mutex.new
      end

      # @return [OpenLanes::Apps::Definition]
      attr_reader :definition

      # @return [String]
      attr_reader :plan

      # Start every process in order and wait for each to be ready.
      #
      # A start whose process lost its port to somebody else between the
      # reservation and the bind is tried once more, from fresh ports.
      #
      # @return [self]
      # @raise [OpenLanes::Apps::Supervisor::StartFailed]
      def start
        launch
        self
      rescue StartFailed => e
        raise unless e.message.match?(RACE)

        launch
        self
      end

      # Stop every process, last started first, and give its port back.
      #
      # @return [void]
      def stop
        @running.keys.reverse_each { halt(it) }
        @ports.each_value { @registry.release(it) }
        @ports.clear
      end

      # Stop one process and start it again on the same port (B5): what a
      # change to its `restart_on` files, or Restart backend, asks for.
      # Its siblings are not touched.
      #
      # @param name [String]
      # @return [Boolean] whether it came back ready
      def restart(name)
        spec = definition.process(name) or raise ArgumentError, "no process #{name.inspect} in this app"
        return false unless @ports.key?(spec.name)

        publish(spec, "restarting")
        halt(spec.name, quietly: true)
        bring_up(spec, nil)
      end

      # @return [Array<OpenLanes::Apps::Status>] the latest of each process, in start order
      def statuses = @mutex.synchronize { definition.processes.filter_map { @statuses[it.name] } }

      # @return [OpenLanes::Apps::Status, nil] the process the Preview tab shows
      def preview = statuses.find(&:preview)

      # @param name [String]
      # @return [Integer, nil] the pid of the process's group leader
      def pid(name) = @running[name.to_s]&.child&.pid

      # @param name [String]
      # @return [Integer, nil]
      def port(name) = @ports[name.to_s]

      private

      # @return [void]
      # @raise [StartFailed]
      def launch
        @ports = definition.processes.to_h { [it.name, @registry.reserve(root: @root, plan:, process: it.name)] }
        @env = definition.processes.to_h { [it.port_env, @ports.fetch(it.name).to_s] }
        definition.processes.each do |spec|
          next if bring_up(spec, "starting")

          reason = @statuses.fetch(spec.name).reason
          stop
          raise StartFailed, reason
        end
      end

      # Spawn, then wait until it is ready, it exits, or time runs out.
      #
      # @param spec [OpenLanes::Apps::ProcessSpec]
      # @param state [String, nil] what to say while it comes up; nil when
      #   that was said already, as a restart does before it stops the old one
      # @return [Boolean] ready
      def bring_up(spec, state)
        publish(spec, state) if state
        running = spawn(spec)
        outcome = await(spec, running)
        return publish(spec, "failed", reason: reason(spec, running, outcome)).then { false } unless outcome == :ready

        publish(spec, "ready", framing: (@framing.check(url(spec), origin: @origin) if spec.preview?))
        true
      end

      # @return [Running]
      def spawn(spec)
        child = Execution::Child.spawn(["sh", "-c", spec.start], chdir: @root, env: @env)
        tail = []
        reader = Thread.new { read(spec.name, child, tail) }
        waiter = Thread.new { child.wait }
        @running[spec.name] = Running.new(spec, child, waiter, reader, tail)
      end

      # @return [void]
      def read(name, child, tail)
        pending = +""
        child.each_chunk do |text|
          pending << text
          while (line = pending.slice!(/\A[^\n]*\n/))
            line = line.chomp
            @mutex.synchronize do
              tail.push(line)
              tail.shift while tail.size > TAIL
            end
            @output&.call(name, line)
          end
        end
      end

      # @return [Symbol] :ready, :exited or :timeout
      def await(spec, running)
        deadline = UI.monotonic + @ready_timeout
        loop do
          return :exited unless running.waiter.alive?
          return :ready if @probe.ready?(@ports.fetch(spec.name), path: spec.ready)
          return :timeout if UI.monotonic >= deadline

          sleep @poll
        end
      end

      # @return [String]
      def reason(spec, running, outcome)
        port = @ports.fetch(spec.name)
        said = if outcome == :exited
                 running.reader.join(1)
                 "#{spec.name} exited with status #{running.waiter.value&.exitstatus.inspect} before it was ready"
               else
                 halt(spec.name, quietly: true)
                 what = spec.ready ? "2xx or 3xx on #{spec.ready}" : "there"
                 "#{spec.name} was given port #{port} and nothing answered #{what} within #{@ready_timeout} s"
               end
        lines = @mutex.synchronize { running.tail.last(5) }
        lines.empty? ? said : "#{said}; it said:\n#{lines.join("\n")}"
      end

      # TERM the process's group, KILL what is left after the grace, and
      # wait for the leader.
      #
      # @return [void]
      def halt(name, quietly: false)
        running = @running.delete(name) or return
        running.child.terminate
        running.waiter.join
        running.reader.join(Execution::Child::DRAIN_GRACE)
        # A process that failed stays failed: its reason is what a person needs.
        publish(running.spec, "stopped") unless quietly || @statuses[name]&.failed?
      end

      # @return [String] what the tab opens: the app's root, not its health check
      def url(spec) = "http://#{Status::HOST}:#{@ports.fetch(spec.name)}/"

      # @return [OpenLanes::Apps::Status]
      def publish(spec, state, framing: nil, reason: nil)
        status = Status.new(plan:,
          branch: @branch,
          process: spec.name,
          state:,
          port: @ports.fetch(spec.name),
          preview: spec.preview?,
          url: url(spec),
          framing:,
          reason:)
        @mutex.synchronize { @statuses[spec.name] = status }
        @publisher&.call(status)
        status
      end
    end
  end
end

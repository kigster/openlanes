# frozen_string_literal: true

module OpenLanes
  # The factory's processes (S1–S5 in docs/decisions/decisions-on-factory-start-stop.md):
  # a supervisor that keeps the engine and the web up, the PID file and title
  # each process gives itself, and the checks every reader makes before it
  # trusts or signals one.
  #
  #   registration = Supervision.registration(Supervision::ENGINE, root:)
  #   Supervision.stopper(root:).call(runs: true)
  #   Supervision.dir(root).entries
  module Supervision
    # The supervisor's role, and its PID file's name.
    SUPERVISOR = "supervisor"

    # The engine's.
    ENGINE = "engine"

    # The control room's server.
    WEB = "web"

    # An `openlanes run`, one file per process.
    RUN = "run"

    # An agent supervisor, one file per running agent (S6). It names itself
    # in a process that loads nothing from the gem, so the word is its.
    AGENT = Execution::AgentSupervisor::ROLE

    # How every listing orders the roles.
    ORDER = [SUPERVISOR, ENGINE, WEB, RUN, AGENT].freeze

    module_function

    # @param root [String] the project root
    # @return [OpenLanes::Supervision::PidDir]
    def dir(root) = PidDir.for(root)

    # This process's own registration.
    #
    # @param role [String]
    # @param root [String]
    # @param details [Hash] +url:+ or +plans:+, for its PID file
    # @return [OpenLanes::Supervision::Registration]
    def registration(role, root:, **details)
      draft = PidFile.new(role:, root:, pid: ::Process.pid, started: nil, **details)
      Registration.new(draft:, dir: dir(root), probe:)
    end

    # @param root [String]
    # @return [OpenLanes::Supervision::Stopper]
    def stopper(root:) = Stopper.new(dir: dir(root), probe:, host:)

    # @return [OpenLanes::Supervision::Supervisor]
    def supervisor(**) = Supervisor.new(host:, **)

    # @param root [String]
    # @return [OpenLanes::Supervision::Detached]
    def detached(root:) = Detached.new(dir: dir(root), host:)

    # In a supervised child: ends this process gracefully once its
    # supervisor is gone, however it went.
    #
    # @return [Thread, nil] nil when this process has no supervisor
    def watch_lifeline = Lifeline.watch

    # In a `--background` child: leaves the terminal's session.
    #
    # @return [void]
    def leave_session = Detached.leave_session

    # The seam every spawn, wait and signal goes through.
    #
    # @return [OpenLanes::Supervision::Host]
    def host = Host::SYSTEM

    # @return [OpenLanes::Supervision::Probe]
    def probe = Probe.new
  end
end

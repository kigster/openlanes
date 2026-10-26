# frozen_string_literal: true

module OpenLanes
  # The app a plan builds, run on this machine (plan 012, M12, M13): the
  # processes `.openlanes.yml` declares under `app:`, started in order on
  # ports from 11100, kept ready, restarted when their files change, and
  # shown in the control room's Preview tab.
  #
  # Plural, like `Agents` and `Adapters`, so it never reads as `Web::App`,
  # the control room's own Sinatra application.
  module Apps
    module_function

    # @param config [OpenLanes::Config]
    # @return [OpenLanes::Apps::Definition, nil] nil when the project declares no app
    def definition(config = Config.current) = config.app

    # This machine's port registry.
    #
    # @return [OpenLanes::Apps::Ports]
    def registry(**) = Ports.new(**)

    # One plan's app, started by {Supervisor#start}. Plan 014 drives this
    # directly in its clean checkout; `openlanes project start` drives it
    # through {.runner}.
    #
    # @param definition [OpenLanes::Apps::Definition]
    # @param root [String] the checkout
    # @param plan [String]
    # @param branch [String]
    # @param publisher [#call, nil]
    # @return [OpenLanes::Apps::Supervisor]
    def supervisor(definition:, root:, plan:, branch:, publisher: nil, **) = Supervisor.new(definition:, root:, plan:, branch:, publisher:, **)

    # @return [OpenLanes::Apps::Watcher]
    def watcher(**) = Watcher.new(**)

    # @return [OpenLanes::Apps::Runner]
    def runner(**) = Runner.new(**)
  end
end

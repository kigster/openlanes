# frozen_string_literal: true

module OpenLanes
  module CLI
    # What `openlanes start` hands its {Supervision::Supervisor}: the engine,
    # with the flags typed and none of the page's, and the page as its
    # launcher would start it.
    class Programs
      # Options for the page, never handed to the engine.
      WEB_OPTIONS = %i[web open port ips all_interfaces admin_credentials].freeze

      # @param options [Hash] what `start` was given
      # @param defaults [Hash] its defaults, `.openlanes.yml` included, which
      #   are left out of argv so config values and secrets stay out of `ps`
      # @param root [String] the project root, every child's working directory
      def initialize(options:, defaults:, root:)
        @options = options
        @defaults = defaults
        @root = root
      end

      # @param web [OpenLanes::Web::Launcher, nil] nil under --no-web
      # @return [Array<OpenLanes::Supervision::Program>]
      def call(web) = [engine, *(page(web) if web)]

      private

      # @return [OpenLanes::Supervision::Program]
      def engine
        flags = Argv.for(EngineCommand.options, @options, defaults: @defaults, except: [*WEB_OPTIONS, :background])
        Supervision::Program.new(role: Supervision::ENGINE,
          argv: [OpenLanes::Web::Launcher::EXE, "engine", "--no-web", *flags],
          options: { chdir: @root },
          essential: true)
      end

      # @param web [OpenLanes::Web::Launcher]
      # @return [OpenLanes::Supervision::Program]
      def page(web)
        Supervision::Program.new(role: Supervision::WEB,
          argv: web.argv,
          env: web.env,
          options: { chdir: @root, %i[out err] => [web.log, "a"] })
      end
    end
  end
end

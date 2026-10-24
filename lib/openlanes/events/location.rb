# frozen_string_literal: true

require "digest"

module OpenLanes
  module Events
    # Where a project's event log lives. The only place that knows.
    #
    # Outside the repo, so the boundary check and `git status` never see it,
    # and beside the run state plan 021.00 is moving out of `.plans/`:
    # `${XDG_STATE_HOME:-~/.local/state}/openlanes/<project>-<6 hex>/events`.
    # If 021.00 settles elsewhere, this method changes and nothing else does.
    module Location
      module_function

      # Hex digits of the root's digest that keep two checkouts named alike apart.
      ROOT_DIGITS = 6

      # @param root [String] the project root
      # @param config [OpenLanes::Config]
      # @param env [Hash]
      # @return [String] absolute
      def dir(root:, config:, env: ENV)
        return config.events_dir if config.events_dir

        File.join(state_home(env), "openlanes", "#{File.basename(root)}-#{digest(root)}", "events")
      end

      # A relative `XDG_STATE_HOME` is invalid under the XDG spec, which says
      # to ignore it, so it is ignored rather than resolved against wherever
      # the process happened to start.
      #
      # @param env [Hash]
      # @return [String]
      def state_home(env)
        state = env["XDG_STATE_HOME"].to_s.strip
        state.start_with?("/") ? state : File.expand_path("~/.local/state")
      end

      # @param root [String]
      # @return [String]
      def digest(root)
        real = File.exist?(root) ? File.realpath(root) : File.expand_path(root)
        Digest::SHA256.hexdigest(real)[0, ROOT_DIGITS]
      end
    end
  end
end

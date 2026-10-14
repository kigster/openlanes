# frozen_string_literal: true

module OpenLanes
  module Apps
    # One process of an app, as `.openlanes.yml` declares it under
    # `app.processes` (M12).
    #
    # @!attribute [r] name
    #   @return [String] `api`, `web`; unique within the app
    # @!attribute [r] start
    #   @return [String] a shell line, run by `sh -c` in the checkout, so
    #     `$PORT_WEB` expands there
    # @!attribute [r] ready
    #   @return [String, nil] an HTTP path that must answer 2xx or 3xx; nil
    #     means a TCP connect is enough
    # @!attribute [r] restart_on
    #   @return [Array<String>] `Dir.glob` patterns, relative to the checkout
    # @!attribute [r] preview
    #   @return [Boolean] the one process the Preview tab shows
    ProcessSpec = Data.define(:name, :start, :ready, :restart_on, :preview) do
      def initialize(name:, start:, ready: nil, restart_on: [], preview: false) = super

      # `PORT_<NAME>`: upcased, anything not a letter or digit as `_`, so
      # `api-v2` is `PORT_API_V2` and a shell can expand it.
      #
      # @return [String]
      def port_env = "PORT_#{name.upcase.gsub(/[^A-Z0-9]/, "_")}"

      # @return [Boolean]
      def preview? = preview == true

      # @return [Hash] as `.openlanes.yml` spells it, defaults left out
      def to_h
        { "name" => name, "start" => start, "ready" => ready,
          "restart_on" => (restart_on unless restart_on.empty?), "preview" => (true if preview?) }.compact
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes version`
    class Version < Dry::CLI::Command
      desc "Print the version and exit"

      # @return [void]
      def call(**) = puts("openlanes #{OpenLanes::VERSION}")
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes states` — the state machine, as a terminal diagram.
    class States < Dry::CLI::Command
      desc "Print a diagram of every state and the transitions between them"

      example [""]

      # @return [void]
      def call(**) = $stdout.write(Presentation.diagram)
    end
  end
end

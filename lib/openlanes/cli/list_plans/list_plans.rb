# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes list-plans` — backs /plan-status.
    class ListPlans < Base
      desc "Print every plan, its state, and its pull requests"

      example ["", "-D .plans", "| less -R"]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        reporter = Presentation.reporter(tree: tree_for(options))
        $stdout.write(reporter.render)

        exit 1 unless reporter.inconsistent.empty?
      end
    end
  end
end

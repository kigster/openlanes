# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes plans` — backs /plan-status.
    class ListPlans < Base
      desc "Print every plan, its state, and its pull requests"

      option :all,
        type:    :boolean,
        default: false,
        desc:    "Also list the plans in archive/, deferred/ and abandoned/"

      example ["", "--all", "-D .plans", "| less -R"]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        tree = tree_for(options)
        reporter = Presentation.reporter(tree: options[:all] ? tree.everything : tree)
        $stdout.write(reporter.render)

        exit 1 unless reporter.inconsistent.empty?
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes unblock NNN…` — hand a stopped plan to the agent that
    # drains its `blocked.md`. Why this is a command of its own rather than
    # part of `run` is told in {Lifecycle::UnblockWorkflow}.
    class Unblock < Base
      desc "Fold answered blocks into a plan's documents and retire blocked.md"

      argument :plans,
        type:     :array,
        required: true,
        desc:     "Which plans to drain: NNN or NNN.MM, e.g. 003 005.01"

      dry_run_option "Invoke no agent; print the questions still open"
      option :agent,
        default: OpenLanes::Lifecycle::UnblockWorkflow::DEFAULT_AGENT,
        desc:    "Hand the folder to a different agent"
      option :root, desc: "Repository root the agent works in (default: the .plans parent)"

      example [
        "003 -n             # what 003 is still waiting on",
        "003                # fold in whatever has been answered",
        "003,005            # both"
      ]

      # @param plans [Array<String>]
      # @param options [Hash]
      # @return [void]
      def call(plans:, **options)
        workflow = OpenLanes::Lifecycle.unblock(tree: tree_for(options),
          agent:   options.fetch(:agent, OpenLanes::Lifecycle::UnblockWorkflow::DEFAULT_AGENT),
          root:    options[:root],
          dry_run: dry_run?(options),
          quiet:   quiet?(options))
        exit(unwrap(workflow.call(plans)))
      end
    end
  end
end

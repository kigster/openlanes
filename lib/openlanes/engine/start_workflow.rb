# frozen_string_literal: true

module OpenLanes
  module Engine
    # `openlanes start` without the command: {RunWorkflow} as a long-lived
    # service. It stays up past every fixed point, rescanning the tree, and
    # treats a missing live board or control room as a refusal rather than a
    # reason to go on headless, since the page is the only way in.
    class StartWorkflow < RunWorkflow
      # Exit status when Redis or the control room is not there to serve.
      UNAVAILABLE = 69

      # @param rescan [Integer] seconds between rescans of .plans while idle
      # @param options [Hash] as for {RunWorkflow#initialize}
      def initialize(rescan:, **)
        super(**)
        @rescan = rescan
      end

      private

      # Always stays, at the rescan asked for, and watches the pull requests
      # a person merges the way a staying `run` does. `--rescan` is seconds
      # and the dispatcher counts ticks, so a 5 passed through unconverted
      # would rescan every 2.5 s.
      #
      # @param _web [OpenLanes::Web::Launcher]
      # @return [Hash]
      def staying(_web, _live = nil) = { stay: true, rescan: Dispatcher.ticks(@rescan), watch: watch }

      # @param message [String]
      # @return [Dry::Monads::Result::Failure]
      def without_live(message)
        refusal("#{message}\n\nopenlanes start needs Redis: its control room is the only way to answer the " \
                "agents' questions. Start redis-server, or pass --redis-url. " \
                "`openlanes run` goes on without it, headless.",
          UNAVAILABLE)
      end

      # @param web [OpenLanes::Web::Launcher]
      # @param live [OpenLanes::Live::Session]
      # @return [Dry::Monads::Result::Failure]
      def without_web(web, live)
        live.close
        refusal("The control room did not answer on #{web.url}, and openlanes start is no use without it. " \
                "Its log: #{web.log}",
          UNAVAILABLE)
      end

      # A project with nothing left to do opens on the idea dialog (W19).
      #
      # @param web [OpenLanes::Web::Launcher]
      # @return [String]
      def browser_url(web)
        open = @tree.subjects.reject { Dispatcher::FINISHED.include?(it.status.key) }
        open.empty? ? "#{web.url}#start" : web.url
      end

      # What the service did, and exit 0: stopping it on purpose is not a
      # failure, and the failed attempts it lived through are listed above
      # the box.
      #
      # @return [Integer] 0
      def finish(runner, attempts, seconds:)
        puts_report(attempts, Engine.tally(attempts:, seconds:).render)
        unless @quiet
          blocked = runner.blocked.map { it.feature.ordinal }
          lines = ["Stopped. Unfinished plans keep their state; openlanes start picks them up again."]
          lines << "Still waiting for answers: #{blocked.join(", ")}" unless blocked.empty?
          success("#{attempts.size} invocation#{"s" unless attempts.size == 1}, " \
                  "#{attempts.count(&:advanced?)} advanced\n\n#{lines.join("\n")}")
        end
        0
      end
    end
  end
end

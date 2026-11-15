# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes start` run again while the factory is up, mixed into
    # {Start}. A second factory is refused, as it always was. One whose
    # control room is down (`openlanes stop --web`, or a page the supervisor
    # gave up on) gets it back instead: the supervisor is asked as
    # `/restart-web` asks it, so the engine and its agents are never touched.
    module Rerun
      private

      # Either way this command ends here: the factory is the other process's.
      #
      # @param holder [OpenLanes::Supervision::PidFile, nil] the running supervisor
      # @param options [Hash]
      # @param root [String] the project root
      # @return [void] returns only when no factory is running
      def running(holder, options, root)
        return unless holder
        # `--no-web` asks for no page, so it is refused as before.
        return restart_control_room(holder, options, root) if options[:web] != false && control_room_down?(holder, root)

        refuse("The factory is already running here (pid #{holder.pid})#{" at #{holder.url}" if holder.url}.\n" \
               "`openlanes stop` stops it; `openlanes status` shows it.",
          75)
      end

      # A supervisor with no URL was started with `--no-web` and has no
      # control room to be down. A web's PID file that fails the check is a
      # crash's leftover, so that page is down too.
      #
      # @param holder [OpenLanes::Supervision::PidFile]
      # @param root [String]
      # @return [Boolean]
      def control_room_down?(holder, root)
        return false unless holder.url

        file = Supervision.dir(root).read(Supervision::WEB)
        !(file && Supervision.probe.verified?(file))
      end

      # @param holder [OpenLanes::Supervision::PidFile]
      # @param options [Hash]
      # @param root [String]
      # @return [void] never returns
      def restart_control_room(holder, options, root)
        found = "The factory is running here (pid #{holder.pid}) with its control room down"
        if dry_run?(options)
          say("#{found}: would restart it at #{holder.url}.")
          dry_run_footer(1, "restart")
        else
          ask_supervisor(holder, root)
          say("#{found}: restarting the control room.")
          puts(holder.url)
        end
        exit(0)
      end

      # @param holder [OpenLanes::Supervision::PidFile]
      # @param root [String]
      # @return [Integer] the supervisor's pid; a refusal never returns
      def ask_supervisor(holder, root)
        Supervision.restart_web(root) ||
          refuse("The factory's supervisor (pid #{holder.pid}) went away before it could be asked. `openlanes status` shows what is left.", 75)
      end

      # `-n` with no factory running.
      #
      # @param options [Hash]
      # @return [void]
      def would_start(options)
        say("Would start the factory#{": the engine alone, with no control room" if options[:web] == false}.")
        dry_run_footer(1, "start")
      end
    end
  end
end

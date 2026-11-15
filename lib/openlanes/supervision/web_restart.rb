# frozen_string_literal: true

require "json"
require "time"

module OpenLanes
  module Supervision
    # `/restart-web` inside the {Supervisor} (plan 069.00): stop the web
    # on purpose, build its page with a {WebRebuild}, leave the outcome in
    # {NOTE} for the new web to tell, then start it again. It holds the
    # slot ({Slot#held}) while the rebuild runs, so its exit is no crash and
    # {Crashes} records nothing; the rebuild itself stays here.
    #
    # Everything here runs on the supervisor's tick, where an error ends
    # `openlanes start` and the engine with it, so nothing here raises: a
    # step that fails is logged, and the web is started again regardless.
    class WebRestart
      # The note a restarted web reads on boot, beside the PID files.
      NOTE = "web-restart.json"

      # @param registration [OpenLanes::Supervision::Registration] the supervisor's own
      # @param host [OpenLanes::Supervision::Host]
      # @param grace [Numeric] seconds the web gets after INT before KILL
      def initialize(registration:, host:, grace:)
        @registration = registration
        @host = host
        @grace = grace
      end

      # Asked from a signal trap, so it only sets a flag.
      #
      # @return [void]
      def ask!
        @asked = true
      end

      # One look, from the supervisor's tick: begins a restart that was
      # asked for, and moves one under way along. Never blocks.
      #
      # @param slots [Array<Slot>]
      # @return [void]
      def tick(slots)
        web = slots.find { it.role == "web" }
        begin_restart(web, slots) if @asked
        step(web) if @rebuild
      rescue StandardError => e
        give_back(web, e)
      end

      # Drops a note no web took, as the supervisor starts: it is from an
      # earlier supervisor's restart, and the web about to boot would tell
      # it as though it had just happened (issue 253).
      #
      # @return [void]
      def forget
        WebRestartNote.drop(note_path)
      rescue StandardError => e
        Log.logger.warn("stale restart note not removed", reason: e.message)
      end

      # The factory is stopping with a restart under way: ends the build
      # and puts the old page back ({WebRebuild#cancel}), and lets go of
      # the slot, so the page a later start serves is a whole one.
      #
      # @param slots [Array<Slot>]
      # @return [void]
      def abandon(slots)
        rebuild = @rebuild or return

        @rebuild = nil
        slots.each { it.held = nil if it.held.equal?(self) }
        Log.logger.info("web rebuild stopped with the factory", outcome: rebuild.cancel.message)
      end

      private

      # @return [String]
      def note_path = File.join(@registration.dir.path, NOTE)

      # Stops the web. A restart already under way swallows a second one.
      # A web the supervisor had given up on is taken back, in its PID
      # file too: `openlanes status` went on listing it as failed after
      # the restart had it running again (issue 253).
      #
      # @param slot [Slot, nil] the web's; nil under --no-web
      # @param slots [Array<Slot>]
      # @return [void]
      def begin_restart(slot, slots)
        @asked = false
        return if slot.nil? || @rebuild

        Log.logger.info("web restart asked", pid: slot.pid)
        @rebuild = WebRebuild.new(host: @host)
        slot.held = self
        slot.due = nil
        @kill_at = @host.clock.monotonic + @grace
        @killed = false
        @host.signaller.call("INT", -slot.pid) if slot.running?
        revive(slot, slots)
      end

      # @param slot [Slot]
      # @param slots [Array<Slot>]
      # @return [void]
      def revive(slot, slots)
        return unless slot.given_up

        slot.given_up = nil
        @registration.update(failed: Slot.failed(slots))
      rescue StandardError => e
        Log.logger.warn("supervisor's PID file not updated", reason: e.message)
      end

      # Once the web has gone, starts the build; once that has settled,
      # leaves its outcome and makes the web due, so the supervisor's own
      # loop starts it on the same port.
      #
      # @param slot [Slot]
      # @return [void]
      def step(slot)
        return hurry(slot) if slot.running?

        outcome = @rebuild.start.poll or return
        @rebuild = nil
        slot.held = nil
        slot.due = @host.clock.monotonic
        note(outcome)
      end

      # The last line of defence for "nothing here raises": whatever a
      # step let through, the restart is given up, the old page put back
      # and the web started again, so one bad restart costs a rebuild and
      # never the factory.
      #
      # @param slot [Slot, nil]
      # @param error [StandardError]
      # @return [void]
      def give_back(slot, error)
        Log.logger.error("web restart failed", reason: error.message)
        rebuild = @rebuild
        @rebuild = nil
        rebuild&.cancel
        return unless slot

        slot.held = nil
        # A web still running is left to run: making it due as well would
        # start a second one beside it.
        slot.due = @host.clock.monotonic unless slot.running?
      end

      # A web that ignores INT is KILLed once its grace has run out. With
      # no deadline the restart waited on it for ever, the slot held and
      # the page unreachable, until someone stopped the factory.
      #
      # @param slot [Slot]
      # @return [void]
      def hurry(slot)
        return if @killed || @host.clock.monotonic < @kill_at

        @killed = true
        Log.logger.warn("web ignored INT, killing it", pid: slot.pid)
        @host.signaller.call("KILL", -slot.pid)
      end

      # A note that cannot be written (a full disk, a PID directory gone
      # read-only) costs the person the build's outcome in the copilot,
      # which is logged here in its place. It must not cost them the web.
      #
      # @param outcome [WebRebuild::Outcome]
      # @return [void]
      def note(outcome)
        Log.logger.info("web rebuilt", outcome: outcome.status)
        WebRestartNote.new(outcome:, at: Time.now).write(note_path)
      rescue StandardError => e
        Log.logger.error("restart note not written", reason: e.message, outcome: outcome.status, message: outcome.message)
      end
    end
  end
end

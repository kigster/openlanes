# frozen_string_literal: true

require "json"
require "time"

module OpenLanes
  module Supervision
    # `/restart-web` inside the {Supervisor} (plan 069.00): stop the web
    # on purpose, build its page with a {WebRebuild}, leave the outcome in
    # {NOTE} for the new web to tell, then start it again. The slot carries
    # the rebuild while it runs, so its exit is no crash and {Crashes}
    # records nothing.
    class WebRestart
      # The note a restarted web reads on boot, beside the PID files.
      NOTE = "web-restart.json"

      # @param dir [OpenLanes::Supervision::PidDir]
      # @param host [OpenLanes::Supervision::Host]
      def initialize(dir:, host:)
        @dir = dir
        @host = host
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
        begin_restart(web) if @asked
        step(web) if web&.rebuild
      end

      private

      # Stops the web. A restart already under way swallows a second one.
      #
      # @param slot [Slot, nil] the web's; nil under --no-web
      # @return [void]
      def begin_restart(slot)
        @asked = false
        return if slot.nil? || slot.rebuild

        Log.logger.info("web restart asked", pid: slot.pid)
        slot.rebuild = WebRebuild.new(host: @host)
        slot.due = nil
        slot.given_up = nil
        @host.signaller.call("INT", -slot.pid) if slot.running?
      end

      # Once the web has gone, starts the build; once that has settled,
      # leaves its outcome and makes the web due, so the supervisor's own
      # loop starts it on the same port.
      #
      # @param slot [Slot]
      # @return [void]
      def step(slot)
        return if slot.running?

        outcome = slot.rebuild.start.poll or return
        slot.rebuild = nil
        note(outcome)
        Log.logger.info("web rebuilt", outcome: outcome.status)
        slot.due = @host.clock.monotonic
      end

      # @param outcome [WebRebuild::Outcome]
      # @return [void]
      def note(outcome)
        FileUtils.mkdir_p(@dir.path)
        File.write(File.join(@dir.path, NOTE), JSON.generate(status: outcome.status, message: outcome.message, at: Time.now.utc.iso8601))
      end
    end
  end
end

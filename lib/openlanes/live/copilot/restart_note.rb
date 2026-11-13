# frozen_string_literal: true

require "json"
require "time"

module OpenLanes
  module Live
    class Copilot
      # What the supervisor left for the control room it restarted
      # (`/restart-web`, plan 069.00): how the page's build went. The web
      # server that read the command died with it, so the new one reads the
      # note on boot, removes it, and tells the person in the copilot.
      class RestartNote
        # @param path [String] the note, `web-restart.json` beside the PID files
        # @param copilot [OpenLanes::Live::Copilot] where the turn goes
        def initialize(path:, copilot:)
          @path = path
          @copilot = copilot
        end

        # Removed before it is told, so a server that crashes after telling
        # it cannot tell it twice.
        #
        # @return [OpenLanes::Live::Copilot::Turn, nil] the turn appended;
        #   nil when there was no note, or none that could be read
        def call
          text = File.read(@path)
          File.delete(@path)
          note = JSON.parse(text)
          at = Time.iso8601(note.fetch("at"))
          @copilot.tell(Turn.new(id: "web-restart-#{at.to_i}", from: "copilot", kind: "text", text: text_for(note), at:))
        rescue Errno::ENOENT, JSON::ParserError, KeyError, TypeError, ArgumentError
          nil
        end

        private

        # @param note [Hash]
        # @return [String]
        def text_for(note)
          verdict = note["status"] == "ok" ? "The control room restarted on a rebuilt page." : "The control room restarted on its old page."
          "#{verdict} #{note["message"].to_s.sub(/\A./, &:upcase)}."
        end
      end
    end
  end
end

# frozen_string_literal: true

require "json"
require "time"

module OpenLanes
  module Supervision
    # The note `/restart-web` leaves beside the PID files for the control
    # room it restarts (plan 069.00): how the page's build went. Its file
    # format lives here alone, so the supervisor that writes it and the web
    # server that reads it cannot disagree on a key or a status (F203).
    #
    # @!attribute [r] outcome
    #   @return [OpenLanes::Supervision::WebRebuild::Outcome]
    # @!attribute [r] at
    #   @return [Time]
    WebRestartNote = Data.define(:outcome, :at) do
      # @param path [String]
      # @return [void]
      def write(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.generate(status: outcome.status, message: outcome.message, at: at.utc.iso8601))
      end

      # Reads the note and removes it, so it is told once.
      #
      # @param path [String]
      # @return [OpenLanes::Supervision::WebRestartNote, nil] nil when there
      #   was no note, or none that could be read
      def self.take(path)
        text = File.read(path)
        File.delete(path)
        note = JSON.parse(text)
        outcome = WebRebuild::Outcome.new(status: note.fetch("status").to_s, message: note.fetch("message").to_s)
        new(outcome:, at: Time.iso8601(note.fetch("at")))
      rescue Errno::ENOENT, JSON::ParserError, KeyError, TypeError, ArgumentError, NoMethodError
        nil
      end
    end
  end
end

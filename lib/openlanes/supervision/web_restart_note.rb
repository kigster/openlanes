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
      # Seconds after which a note is no longer news. A web that never
      # came back leaves its note behind, and the next server to boot,
      # hours or days on, announced a restart nobody then remembered
      # (issue 253). A restarted web boots within seconds of the note.
      const_set(:STALE_AFTER, 300)

      # @param path [String]
      # @return [void]
      def write(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.generate(status: outcome.status, message: outcome.message, at: at.utc.iso8601))
      end

      # Reads the note and removes it, so it is told once. Read as UTF-8
      # whatever the locale: a build's output is, and under `LC_ALL=C` the
      # note would otherwise fail to parse and be lost.
      #
      # @param path [String]
      # @param now [Time]
      # @return [OpenLanes::Supervision::WebRestartNote, nil] nil when there
      #   was no note, none that could be read, or one too old to tell
      def self.take(path, now: Time.now)
        text = File.read(path, encoding: Encoding::UTF_8)
        File.delete(path)
        note = JSON.parse(text)
        outcome = WebRebuild::Outcome.new(status: note.fetch("status").to_s, message: note.fetch("message").to_s)
        at = Time.iso8601(note.fetch("at"))
        new(outcome:, at:) if now - at <= self::STALE_AFTER
      rescue SystemCallError, JSON::ParserError, KeyError, TypeError, ArgumentError, NoMethodError
        nil
      end

      # Removes a note nobody took. The supervisor does this as it starts:
      # whatever is there then was left by an earlier one.
      #
      # @param path [String]
      # @return [void]
      def self.drop(path) = FileUtils.rm_f(path)
    end
  end
end

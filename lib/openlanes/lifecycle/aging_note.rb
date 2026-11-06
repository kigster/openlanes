# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # The paragraph {Aging} leaves in `delayed.md` when it sets a blocked plan
    # aside, and the one place that knows its words.
    #
    # A plan aging deferred is still waiting on its questions; a plan a person
    # deferred chose to wait. Both are 💤, and aging appends to a `delayed.md`
    # that is already there, so neither the emoji nor the file tells them
    # apart: only this text does. Without it the deferred plan's questions
    # left the page and were never drained, and the plan sat in 💤 for good.
    module AgingNote
      # What brings the plan back, in words 💤's own invariant accepts.
      TRIGGER = "Trigger: revisit after the block is answered. The questions are still in `blocked.md`."

      # One note as {.text} writes it, with the date and reason it carries.
      PATTERN = /^Deferred by aging on [^\n]*\n\n#{Regexp.escape(TRIGGER)}\n?/

      # The heading a fresh `delayed.md` opens with.
      HEADING = /\A# Deferred: [^\n]*\n/

      module_function

      # @param subject [OpenLanes::Plans::Subject]
      # @param on [Time] when the sweep deferred it
      # @param blocked_for [String] "15 days"
      # @param fresh [Boolean] whether the note starts a new `delayed.md`
      # @return [String]
      def text(subject, on:, blocked_for:, fresh:)
        heading = fresh ? "# Deferred: #{subject.feature.ordinal} #{subject.feature.slug}\n\n" : "\n"
        "#{heading}Deferred by aging on #{on.strftime("%Y-%m-%d")}: blocked #{blocked_for} with no answer, " \
          "and no open plan depends on it.\n\n#{TRIGGER}\n"
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean] whether `delayed.md` carries an aging note
      def on?(subject) = PATTERN.match?(subject.read("delayed.md").to_s)

      # A 💤 the sweep made that still has its questions: waiting on a person
      # the way a ⭕ is, so it is shown and drained like one.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def waiting?(subject) = subject.status.key == :deferred && subject.file?("blocked.md") && on?(subject)

      # Strip every aging note from the folder's `delayed.md`, once the block
      # it waited on is gone. The file goes too when nothing a person wrote is
      # left in it; whatever a person did write stays, and keeps the plan 💤.
      #
      # @param dir [String] the plan folder
      # @return [Boolean] whether a note was retired
      def retire(dir)
        path = File.join(dir, "delayed.md")
        return false unless File.file?(path)

        body = File.read(path)
        rest = body.gsub(PATTERN, "")
        return false if rest == body

        rest.sub(HEADING, "").strip.empty? ? File.delete(path) : File.write(path, "#{rest.rstrip}\n")
        true
      end
    end
  end
end

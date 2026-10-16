# frozen_string_literal: true

require "digest"
require "tmpdir"

module OpenLanes
  module Engine
    # What is left of the run's own column-format log now that every event
    # goes through {Log}: the clock and the status cell the terminal's lines
    # are drawn with, and where a spawned server's raw output is kept.
    #
    # The fixed-column file it used to write is gone. Two files saying the
    # same thing in two formats is the duplication this codebase keeps
    # paying for; `log/development.log` is now the one record of a run.
    module ProgressLog
      # Wall clock only. A terminal line answers "when", and the date is the day's.
      TIME_FORMAT = "%H:%M:%S"

      # Cells given to the emoji, and the gap after it. Many terminal fonts draw
      # a colour emoji wider than its two cells, and with one space it overlapped
      # the label's first letter ("🔴Changes").
      EMOJI_WIDTH = 2
      EMOJI_GAP = "  "

      # Hex digits of the checkout's path in a default file's name.
      CHECKOUT_DIGITS = 6

      class << self
        # Where a spawned process's raw STDOUT and STDERR go: the temp
        # directory, under the checkout's directory name and a short digest
        # of its full path. The name alone collided: `~/a/minesweeper` and
        # `~/b/minesweeper` both appended to `openlanes-minesweeper.log`, and
        # two runs' lines read as one.
        #
        # @param root [String] the checkout
        # @param kind [String, nil] which process writes it, e.g. "web"
        # @return [String] e.g. "/tmp/openlanes-web-minesweeper-3f9a1c.log"
        def default_path(root, kind: nil)
          root = File.expand_path(root)
          digest = Digest::SHA256.hexdigest(root)[0, CHECKOUT_DIGITS]
          File.join(Dir.tmpdir, "#{["openlanes", kind, File.basename(root), digest].compact.join("-")}.log")
        end

        # The emoji fitted to {EMOJI_WIDTH} and followed by {EMOJI_GAP}, then the
        # label. A value with no label (or none at all) passes through.
        #
        # @param status [String, nil] emoji and label, e.g. "⭐ Planned"
        # @return [String, nil]
        def status_cell(status)
          emoji, label = status.to_s.split(" ", 2)
          return status if label.nil?

          "#{UI.fit(emoji, EMOJI_WIDTH)}#{EMOJI_GAP}#{label}"
        end
      end
    end
  end
end

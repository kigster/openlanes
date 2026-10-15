# frozen_string_literal: true

require "date"
require "json"
require "open3"

module OpenLanes
  module Vcs
    # The date a plan reached the state that sends it into an inactive
    # subfolder, for the `[YYYY-MM-DD]` its archived name carries (N3).
    #
    # A state change is a folder rename, so the date of the folder's latest
    # rename is the date it got there. Git knows it, through a file inside the
    # folder: `--follow --diff-filter=R` returns the rename itself, where
    # `git log -1 -- <folder>` returns whichever edit came last, and a spec
    # touched up a month after the merge would date the archive by the edit.
    #
    # Git does not always know. The folder may never have been committed, the
    # clone may be shallow, or the tree may not be a repository at all; then
    # `state.json`'s `updated_at`, which the harness writes on every state
    # change, and failing that, today.
    module RenameDate
      # Files tried first; a folder holding none of them (a ❌ plan may hold
      # only `discarded.md`) is followed through whichever file it does hold.
      PROBES = %w[spec.md plan.md pull-requests.md].freeze

      class << self
        # @param dir [String] a plan folder
        # @param today [Date] the last resort
        # @return [Date]
        def for(dir, today: Date.today) = from_git(dir) || from_state(dir) || today

        private

        # @param dir [String]
        # @return [Date, nil]
        def from_git(dir)
          probe = probe_in(dir) or return nil

          out, status = Open3.capture2("git",
            "-C",
            dir,
            "log",
            "--follow",
            "--diff-filter=R",
            "--format=%cI",
            "-1",
            "--",
            probe,
            err: File::NULL)
          status.success? ? parse(out.strip) : nil
        rescue SystemCallError
          nil
        end

        # @param dir [String]
        # @return [String, nil] a file name inside +dir+
        def probe_in(dir)
          PROBES.find { File.file?(File.join(dir, it)) } ||
            Dir.children(dir).sort.find { File.file?(File.join(dir, it)) && it != Plans::Lock::FILENAME }
        end

        # @param dir [String]
        # @return [Date, nil]
        def from_state(dir)
          parse(JSON.parse(File.read(File.join(dir, Plans::PlanState::FILENAME)))["updated_at"])
        rescue SystemCallError, JSON::ParserError, TypeError
          nil
        end

        # @param text [String, nil] an ISO-8601 timestamp
        # @return [Date, nil]
        def parse(text)
          return nil if text.to_s.empty?

          Date.iso8601(text.to_s[0, 10])
        rescue Date::Error
          nil
        end
      end
    end
  end
end

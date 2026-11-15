# frozen_string_literal: true

require "open3"

# Helpers for the memory integration specs.
module MemoryFixture
  # A `TTY::Command` stand-in that runs git for real and records each `gh`
  # call as the pull request it would have opened, so a spec drives the
  # real {OpenLanes::Vcs::Publisher} against a bare origin with GitHub the
  # only seam.
  class GitOnly
    # What `TTY::Command#run` returns, as far as the publisher reads it.
    Ran = Data.define(:out)

    # @param opened [Array<Hash>] receives `argv`, `body` and `files` per pull request
    def initialize(opened) = @opened = opened

    # @return [Ran]
    def run(*argv, chdir:)
      return gh(argv, chdir) if argv.first == "gh"

      out, status = Open3.capture2e(argv.first, *LessonsFixture::LESSONS_GIT, *argv.drop(1), chdir:)
      raise "#{argv.join(" ")}: #{out}" unless status.success?

      Ran.new(out:)
    end

    private

    def gh(argv, chdir)
      files, = Open3.capture2("git", "show", "--name-only", "--format=", "HEAD", chdir:)
      @opened << { argv:, body: File.read(argv[argv.index("-F") + 1]), files: files.lines.map(&:strip) }
      Ran.new(out: "https://example.com/pr/9\n")
    end
  end
end

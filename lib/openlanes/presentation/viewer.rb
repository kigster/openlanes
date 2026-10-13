# frozen_string_literal: true

module OpenLanes
  module Presentation
    # Hands Markdown files to a renderer outside this process: the system
    # viewer via `open`, or mdfried in the terminal.
    #
    # Both paths shell out, so the class takes its two effects as lambdas and
    # the specs assert on the commands instead of launching viewers on the box
    # running the suite.
    class Viewer
      # What to run when mdfried is asked for but not installed. Homebrew is the
      # one package manager the toolchain already assumes (see the Brewfile
      # convention), so there is no fallback chain to get wrong.
      INSTALL = "brew install mdfried >/dev/null"

      # How to notice mdfried is missing without depending on `which`, which
      # differs across shells; `command -v` is POSIX.
      DETECT = "command -v mdfried >/dev/null"

      # @param launch [#call] runs a command, returns truthy on success
      # @param pipe [#call] runs a command, yielding its stdin as an IO
      def initialize(launch: ->(*cmd) { system(*cmd) },
        pipe: ->(cmd, &block) { IO.popen(cmd, "w", &block) })
        @launch = launch
        @pipe = pipe
      end

      # Opens each file in whatever the system has configured for Markdown.
      #
      # @param paths [Array<String>]
      # @return [void]
      def open(paths)
        Array(paths).each { |path| @launch.call("open", path) }
      end

      # Streams each file's content into mdfried, installing it first when it
      # is missing.
      #
      # @param paths [Array<String>]
      # @return [void]
      # @raise [OpenLanes::Error] when mdfried is absent and brew cannot fix that
      def mdfried(paths)
        ensure_mdfried!
        Array(paths).each do |path|
          @pipe.call("mdfried") { |io| io.write(File.read(path)) }
        end
      end

      private

      # @return [void]
      # @raise [OpenLanes::Error]
      def ensure_mdfried!
        return if @launch.call(DETECT)

        @launch.call(INSTALL) or
          raise Error, "mdfried is not installed, and `brew install mdfried` failed"
      end
    end
  end
end

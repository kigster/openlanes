# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module CLI
    # `openlanes docs` — regenerate the conventions document.
    class Docs < Base
      standalone!
      desc "Generate the conventions document from the state machine itself"

      # STDOUT unless a file is named. The default used to be a file in the
      # user's home, so an agent running `openlanes docs` to *read* the
      # conventions overwrote ~/.agents/context/workflow.md, untracked and
      # unrecoverable, while the help promised STDOUT.
      option :output,
        aliases: ["-o"],
        desc:    "Write here instead of STDOUT; - for STDOUT"

      example ["                                  # print it", "-o ~/.agents/context/workflow.md  # write it"]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        document = Presentation.documentation

        path = options[:output]
        if path && path != "-"
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, document)
          # Argument form, so a path with a space or a quote reaches mdformat whole.
          system("mdformat", "--wrap", "no", path, err: File::NULL, out: File::NULL)
          success("created workflow description in [#{path}]") unless quiet?(options)
        else
          $stdout.write(document)
        end
      end
    end
  end
end

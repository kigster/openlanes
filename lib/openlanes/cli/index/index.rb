# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes index` — the plans as one browsable page.
    class Index < Base
      desc "Create or update .plans/INDEX.md — a global index of every plan."

      option :output,
        aliases: ["-o"],
        desc:    "Write somewhere other than <plans>/INDEX.md; - for STDOUT"
      option :project,
        aliases: ["-p"],
        desc:    "Heading for the page, default: the repository's directory name"

      example [
        "                     # write .plans/INDEX.md",
        "-o -                 # print it instead",
        "-p 'Equilibris App'  # override the heading"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        index = OpenLanes::Plans.index(tree: tree_for(options), project: options[:project])

        if options[:output] == "-"
          $stdout.write(index.render)
          return
        end

        path = index.write(typed_path(options[:output]))
        puts path
        return if quiet?(options)

        success("Wrote #{path}\n\nRegenerate it after any `resync dirs`, which renames folders\nand would otherwise leave every link here pointing at nothing.")
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module CLI
    module API
      # `openlanes api docs` — every plan's `openapi.yaml`, and how to read it.
      #
      # Read-only, so there is nothing to preview and no `--dry-run`.
      class Docs < Base
        desc "List the openapi.yaml files in the plan folders, and check each one parses"

        example [
          "                # every contract, with the command that renders it",
          "-D other/.plans # another plans directory"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          quiet = quiet?(options)
          tree = tree_for(options)
          result = OpenLanes::Presentation.api_docs.call(tree)

          result.found.each { puts entry(it) }
          # Plain `path: reason` lines rather than {UI#warn}'s box, which
          # truncates the path, the one thing a person needs. This shape is
          # also what an editor's quickfix list already reads.
          result.problems.each { Kernel.warn("#{shown(it.path)}: #{it.reason}") }
          UI.line("No #{OpenLanes::Presentation::ApiDocs::FILE} in #{tree.dir}") if result.found.empty? && result.ok? && !quiet
          exit 65 unless result.ok?
        end

        private

        # A hosted Redoc page (redocly.github.io/redoc/?url=…) only loads a
        # URL the browser can fetch over HTTP, and a path on this disk is not
        # one, so that link would open on an error. Redocly's own CLI renders
        # the local file to one static HTML page, offline, which is the honest
        # thing to point at.
        #
        # @param found [OpenLanes::Presentation::ApiDocs::Found]
        # @return [String]
        def entry(found)
          path = shown(found.path)
          title = [found.title, "OpenAPI #{found.version}"].compact.join(" — ")
          html = File.join(File.dirname(path), "openapi.html")
          "#{path}  (#{title})\n  npx @redocly/cli build-docs #{path.shellescape} -o #{html.shellescape}"
        end

        # Relative to where the command runs, the project root, so the line
        # can be pasted back into a shell as it is. A `-D` outside the root
        # stays absolute: a path climbing out with `../..` reads as a typo.
        #
        # @param path [String]
        # @return [String]
        def shown(path)
          root = "#{Dir.pwd}/"
          path.start_with?(root) ? path.delete_prefix(root) : path
        end
      end
    end
  end
end

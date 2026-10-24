# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module Setup
    # `docs/decisions/stack.md`: the same fields `stack:` holds in
    # `.openlanes.yml`, in prose, for the agents and people who read docs
    # rather than config. Rewritten whole on every `init`, never appended.
    class StackDocument
      # Where it lives, relative to the root.
      PATH = "docs/decisions/stack.md"

      # Field → the label it is written under. `from` and `to` have a section of their own.
      LABELS = {
        language:    "Language",
        frameworks:  "Frameworks",
        front_end:   "Front end",
        persistence: "Persistence",
        caching:     "Caching",
        logins:      "Logins",
        deployment:  "Deployment",
        domain:      "Domain"
      }.freeze

      # @param stack [OpenLanes::Setup::Stack] never empty
      def initialize(stack)
        @stack = stack
      end

      # @return [String] the markdown
      def render
        fields = @stack.to_h
        lines = LABELS.filter_map do |field, label|
          value = fields[field]
          "- **#{label}:** #{Array(value).join(", ")}" if value
        end
        text = "# Stack\n\nRecorded by `openlanes init`; `openlanes init --reconfigure` rewrites it.\n\n#{lines.join("\n")}\n"
        text << port(fields) if fields[:from] || fields[:to]
        text
      end

      # @param root [String]
      # @return [String] the file written
      def write(root)
        path = File.join(root, PATH)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, render)
        path
      end

      private

      # @return [String]
      def port(fields)
        "\n## Port\n\nThe code is being ported from #{fields[:from] || "the current stack"} " \
          "to #{fields[:to] || "a stack still to be named"}.\n"
      end
    end
  end
end

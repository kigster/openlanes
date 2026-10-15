# frozen_string_literal: true

require "yaml"

module OpenLanes
  module Presentation
    # The OpenAPI documents plans carry, one `openapi.yaml` per plan folder,
    # gathered so a person can find and render them.
    #
    # This is a smoke check, not a validator: a file is a problem when it is
    # not YAML, or lacks the two top-level keys every OpenAPI document has.
    # A real validator would pull in a JSON Schema stack for a check whose
    # job is to catch the file an agent half-wrote, which these two do.
    class ApiDocs
      # The name an agent writes its contract under, in its plan's folder.
      FILE = "openapi.yaml"

      # Keys whose absence means the file is not an OpenAPI document at all.
      REQUIRED_KEYS = %w[openapi paths].freeze

      # One document that passed the check.
      #
      # @!attribute path [String] absolute path to the file
      # @!attribute title [String, nil] `info.title`, when it has one
      # @!attribute version [String] the `openapi:` value, such as "3.1.0"
      Found = Data.define(:path, :title, :version)

      # One document that did not.
      #
      # @!attribute path [String] absolute path to the file
      # @!attribute reason [String] what is wrong, in a sentence
      Problem = Data.define(:path, :reason)

      # Everything one look at a tree found.
      #
      # @!attribute found [Array<Found>]
      # @!attribute problems [Array<Problem>]
      Result = Data.define(:found, :problems) do
        # @return [Boolean] true when no file failed the check
        def ok? = problems.empty?
      end

      # @param tree [OpenLanes::Plans::Tree]
      # @return [Result] files ordered by path, so plan order
      def call(tree)
        found = []
        problems = []
        Dir.glob(File.join(tree.dir, "*", FILE)).each do |path|
          outcome = inspect_file(path)
          (outcome.is_a?(Problem) ? problems : found) << outcome
        end
        Result.new(found:, problems:)
      end

      private

      # @param path [String]
      # @return [Found, Problem]
      def inspect_file(path)
        document = YAML.safe_load_file(path, permitted_classes: Frontmatter::PERMITTED_CLASSES, aliases: true)
        return Problem.new(path:, reason: "is not a YAML mapping") unless document.is_a?(Hash)

        missing = REQUIRED_KEYS.reject { document.key?(it) }
        unless missing.empty?
          return Problem.new(path:, reason: "has no top-level #{missing.map { "#{it}:" }.join(" or ")}")
        end

        Found.new(path:, title: document.dig("info", "title"), version: document["openapi"].to_s)
      rescue Psych::Exception => e
        # The parser's own message carries the line and column, which is
        # what a person needs to find the bad indent.
        Problem.new(path:, reason: "does not parse as YAML: #{e.message}")
      end
    end
  end
end

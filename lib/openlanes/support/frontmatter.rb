# frozen_string_literal: true

require "date"
require "yaml"

module OpenLanes
  # Splits a markdown file into its YAML frontmatter and its body.
  #
  # The agent definitions and `create --from` both read frontmatter, and both
  # used to call `YAML.safe_load` on their own. Its defaults refuse to build a
  # `Date`, so an ordinary `date: 2026-08-31` raised Psych::DisallowedClass and
  # `create` reported a missing `title:` on a file whose title was right there.
  # One parser, one list of permitted classes, so that cannot happen twice.
  module Frontmatter
    # rubocop: disable Lint/OrAssignmentToConstant
    # Frontmatter, then body.
    PATTERN ||= /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

    # Dates and timestamps are ordinary frontmatter, so they load. Nothing else
    # does: the point of `safe_load` is that a seed file cannot name a class.
    PERMITTED_CLASSES ||= [Date, Time].freeze
    # rubocop: enable Lint/OrAssignmentToConstant

    class << self
      # @param content [String] a whole markdown file
      # @return [Array(Hash, String)] the frontmatter and the body. A file with
      #   no frontmatter is all body, and frontmatter that is not a mapping —
      #   a bare list, a lone string — reads as no keys rather than raising.
      # @raise [Psych::Exception] when the frontmatter is not valid YAML
      def split(content)
        match = PATTERN.match(content) or return [{}, content]

        meta = YAML.safe_load(match[1], permitted_classes: PERMITTED_CLASSES)
        [meta.is_a?(Hash) ? meta : {}, match[2]]
      end
    end
  end
end

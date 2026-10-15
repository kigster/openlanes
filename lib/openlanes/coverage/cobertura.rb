# frozen_string_literal: true

module OpenLanes
  module Coverage
    # Cobertura XML. Only the root `<coverage>` element is read:
    # `lines-covered` and `lines-valid` when both are there (gcovr writes
    # them), else `line-rate`, a 0–1 decimal that some producers round.
    #
    # The root tag is matched rather than parsed with an XML library, because
    # its attributes are the whole of what is needed and the gem has no XML
    # dependency to spend on it.
    module Cobertura
      ROOT = /<coverage\b([^>]*)>/m

      module_function

      # @param text [String]
      # @return [Array(Numeric, Numeric)] covered, relevant
      # @raise [OpenLanes::Coverage::Malformed]
      def parse(text)
        root = text[ROOT, 1] or raise Malformed, "no <coverage> element"
        attributes = root.scan(/([\w-]+)\s*=\s*["']([^"']*)["']/).to_h

        covered, valid = attributes.values_at("lines-covered", "lines-valid")
        return [whole(covered), whole(valid)] if covered && valid

        rate = attributes["line-rate"] or raise Malformed, "<coverage> has neither lines-valid nor line-rate"
        [rational(rate), 1]
      end

      # @return [Integer]
      def whole(text)
        Integer(text, 10)
      rescue ArgumentError
        raise Malformed, "#{text.inspect} is not a line count"
      end

      # @return [Rational]
      def rational(text)
        value = Rational(text)
        raise Malformed, "line-rate #{text.inspect} is outside 0 to 1" unless value.between?(0, 1)

        value
      rescue ArgumentError, ZeroDivisionError
        raise Malformed, "line-rate #{text.inspect} is not a number"
      end
    end
  end
end

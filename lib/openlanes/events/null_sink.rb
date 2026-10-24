# frozen_string_literal: true

module OpenLanes
  module Events
    # The sink when events are off, the default: answers every call and
    # creates nothing, so a single-machine install that never asked for a
    # log never finds a directory it did not make.
    class NullSink
      # @return [nil]
      def run = nil

      # @return [Boolean]
      def enabled? = false

      # @return [OpenLanes::Events::NullSink]
      def with(**) = self

      # @return [nil]
      def record(...) = nil

      # @return [nil]
      def emit(_event) = nil
    end
  end
end

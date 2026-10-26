# frozen_string_literal: true

module OpenLanes
  module Supervision
    # One child of the {Supervisor} and its history: the process running
    # it now, when it is due to start again, and why it no longer is.
    class Slot
      # @param program [OpenLanes::Supervision::Program]
      # @param crashes [OpenLanes::Supervision::Crashes]
      def initialize(program, crashes)
        @program = program
        @crashes = crashes
        @restarts = 0
      end

      # @return [OpenLanes::Supervision::Program]
      attr_reader :program

      # @return [OpenLanes::Supervision::Crashes]
      attr_reader :crashes

      # @return [Integer, nil] while it runs
      attr_accessor :pid

      # @return [Float, nil] when it is due to start again
      attr_accessor :due

      # @return [String, nil] why it is no longer restarted
      attr_accessor :given_up

      # @return [Integer]
      attr_accessor :restarts

      # @return [String]
      def role = program.role

      # @return [Boolean]
      def running? = !pid.nil?

      # @param now [Float]
      # @return [Boolean] whether a restart it waits for has come round
      def due?(now) = !due.nil? && now >= due
    end
  end
end

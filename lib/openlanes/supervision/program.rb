# frozen_string_literal: true

module OpenLanes
  module Supervision
    # One child a {Supervisor} keeps running.
    #
    # @!attribute [r] role
    #   @return [String] engine or web; the name of its PID file
    # @!attribute [r] argv
    #   @return [Array<String>]
    # @!attribute [r] env
    #   @return [Hash{String => String}] added to the supervisor's own
    # @!attribute [r] options
    #   @return [Hash] for `Process.spawn`: chdir, where its output goes
    # @!attribute [r] essential
    #   @return [Boolean] whether the factory ends when this child ends of
    #     its own accord: the engine, after Stop All Local or a refusal
    Program = Data.define(:role, :argv, :env, :options, :essential) do
      # @param role [String]
      # @param argv [Array<String>]
      # @param env [Hash{String => String}]
      # @param options [Hash]
      # @param essential [Boolean]
      def initialize(role:, argv:, env: {}, options: {}, essential: false)
        super
      end
    end
  end
end

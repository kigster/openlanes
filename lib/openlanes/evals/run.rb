# frozen_string_literal: true

require "json"

module OpenLanes
  module Evals
    # What one run spent, and where it left the folder.
    #
    # A live run measures all three. A recording carries them in `run.json`,
    # because a directory on disk cannot say how long it took to write.
    #
    # @!attribute [r] seconds
    #   @return [Float, nil] wall clock
    # @!attribute [r] tokens
    #   @return [Integer, nil] sent plus generated
    # @!attribute [r] state
    #   @return [Symbol, nil] the status key the folder ended in, when its
    #     name cannot say so itself
    Run = Data.define(:seconds, :tokens, :state) do
      def initialize(seconds: nil, tokens: nil, state: nil)
        super(seconds: seconds&.to_f, tokens: tokens&.to_i, state: state&.to_sym)
      end

      # @param path [String] a `run.json`
      # @return [OpenLanes::Evals::Run] empty when the file is absent
      def self.load(path)
        return new unless File.file?(path)

        data = JSON.parse(File.read(path))
        new(seconds: data["seconds"], tokens: data["tokens"], state: data["state"])
      end
    end
  end
end

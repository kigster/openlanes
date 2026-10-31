# frozen_string_literal: true

module OpenLanes
  module Setup
    module ProjectForm
      # What the form talks to a person through. `openlanes init` passes none
      # under `-y`, so that path holds no prompt and no extractor.
      #
      # @!attribute prompt
      #   @return [TTY::Prompt]
      # @!attribute extractor
      #   @return [OpenLanes::Setup::Extractor, nil] nil when nothing can read a description
      # @!attribute out
      #   @return [IO] where the form talks, never STDOUT
      Terminal = Data.define(:prompt, :extractor, :out) do
        def initialize(prompt:, extractor: nil, out: $stderr) = super
      end
    end
  end
end

# frozen_string_literal: true

require "delegate"

module OpenLanes
  module Setup
    module ProjectForm
      # One step, its words wrapped for the terminal. The DSL's text stays whole,
      # since each front end wraps to its own width, and every widget reads
      # `question` and `option_labels`, so this one place covers them all.
      class WrappedNode < SimpleDelegator
        # Columns a list spends on its pointer and checkbox.
        LIST_MARGIN = 4

        # @param node [Inquirex::Node]
        # @param width [Integer]
        def initialize(node, width)
          super(node)
          @width = width
        end

        # @return [String]
        def question = ProjectForm.wrap(__getobj__.question, @width)

        # A label's later lines are indented past the pointer, so a long choice
        # reads as one choice.
        #
        # @return [Hash{String => String}, nil]
        def option_labels
          __getobj__.option_labels&.transform_values do |label|
            ProjectForm.wrap(label, @width - LIST_MARGIN).gsub("\n", "\n#{" " * LIST_MARGIN}")
          end
        end
      end
    end
  end
end

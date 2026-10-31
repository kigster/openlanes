# frozen_string_literal: true

require "inquirex"

module OpenLanes
  module Setup
    module ProjectForm
      # What the closed lists cannot catch, refused at its own question rather
      # than after every later one has been answered.
      class Validator < Inquirex::Validation::Adapter
        # @param node [Inquirex::Node]
        # @param input [Object]
        # @return [Inquirex::Validation::Result]
        def validate(node, input)
          error = problem(node.id, input)
          Inquirex::Validation::Result.new(valid: error.nil?, errors: [error].compact)
        end

        private

        # @return [String, nil]
        def problem(id, input)
          return "a name is required" if id == :project && input.to_s.strip.empty?
          return "enter a whole number above zero, or leave it blank" if id == :jobs && !input.nil? && input.to_i < 1
          return nil unless id.to_s.end_with?("_projects")

          "name folders inside this repository" if ProjectForm::Answers.paths(input).any? { outside?(it) }
        end

        # @return [Boolean]
        def outside?(path) = path.start_with?("/", "~") || path.split("/").include?("..")
      end
    end
  end
end

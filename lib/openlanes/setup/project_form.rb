# frozen_string_literal: true

require "strings"
require "tty-screen"

module OpenLanes
  module Setup
    # The questionnaire `openlanes init` opens with: `project_form/dsl.rb` is the
    # form, and this is how the terminal runs it and how a web front end gets it.
    module ProjectForm
      # The form's source of truth.
      DSL = File.join(__dir__, "project_form", "dsl.rb")

      # No question runs wider than this, however wide the screen.
      MAX_WIDTH = 115

      module_function

      # @return [Inquirex::Definition]
      def definition
        @definition ||= begin
          require "inquirex"
          require "inquirex-llm"
          require "inquirex/tty"
          Inquirex::TTY::FlowLoader.load(DSL)
        end
      end

      # @return [Inquirex::Engine] a fresh run of the form
      def engine
        form = definition
        Inquirex::Engine.new(form, validator: Validator.new)
      end

      # @return [String] what the inquirex-webui and inquirex-widget front ends read
      def to_json(*) = definition.to_json(*)

      # @param screen [Integer] the terminal's columns
      # @return [Integer]
      def width(screen = TTY::Screen.width) = [MAX_WIDTH, screen - 1].min

      # @param text [String]
      # @param columns [Integer]
      # @return [String] the text on lines no wider than the columns
      def wrap(text, columns = width) = text.lines.map { Strings::Wrap.wrap(it.strip, columns) }.join("\n")

      # @return [Array<Symbol>] the flags a form answer can come from
      def flags = %i[project starts jobs merge_by desired_codebase_quality]
    end
  end
end

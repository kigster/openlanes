# frozen_string_literal: true

require "delegate"

module OpenLanes
  module Setup
    # A prompt that leaves a blank line between one question and the next,
    # so `openlanes init`'s dozen questions read as separate questions
    # rather than one wall of text. The first question is not padded: it
    # follows the command line directly.
    #
    # @example
    #   prompt = SpacedPrompt.new(TTY::Prompt.new(output: $stderr), out: $stderr)
    #   prompt.ask("Project name:")  # no blank line
    #   prompt.yes?("Overwrite?")    # a blank line first
    class SpacedPrompt < SimpleDelegator
      # @param prompt [TTY::Prompt]
      # @param out [IO] where the blank line goes: the prompt's own output
      def initialize(prompt, out: $stderr)
        super(prompt)
        @out = out
        @asked = false
      end

      # @return [String, nil] see TTY::Prompt#ask
      def ask(...) = spaced { super }

      # @return [Object] see TTY::Prompt#select
      def select(...) = spaced { super }

      # @return [Array<Object>] see TTY::Prompt#multi_select
      def multi_select(...) = spaced { super }

      # @return [Boolean] see TTY::Prompt#yes?
      def yes?(...) = spaced { super }

      # @return [Boolean] see TTY::Prompt#no?
      def no?(...) = spaced { super }

      private

      # @return [IO]
      attr_reader :out

      # @return [Boolean] whether a question has been asked yet
      attr_accessor :asked

      # @yieldreturn [Object] the answer
      # @return [Object] the answer
      def spaced
        out.puts if asked
        self.asked = true
        yield
      end
    end
  end
end

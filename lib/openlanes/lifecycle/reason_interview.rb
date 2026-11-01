# frozen_string_literal: true

module OpenLanes
  module Lifecycle
    # Asks why, plan by plan, and writes nothing: every answer is in hand
    # before the first folder moves, so Ctrl-C halfway leaves nothing half done (X3).
    class ReasonInterview
      OTHER = "Some other reason"

      TRASH_CHOICES = [
        "This plan is already implemented, but outside of OpenLanes",
        "This plan conflicts with another plan so we are scrapping it",
        "This plan is no longer relevant",
        "This plan is poorly spec'd and needs to be re-started anew",
        OTHER
      ].freeze

      # @param prompt [TTY::Prompt]
      # @param verb [String] e.g. `trashing`
      # @param choices [Array<String>, nil] nil asks for free text only
      # @param out [IO] where the plans are listed
      def initialize(prompt:, verb:, choices: nil, out: $stderr)
        @prompt = prompt
        @verb = verb
        @choices = choices
        @out = out
      end

      # @param subjects [Array<OpenLanes::Plans::Subject>]
      # @return [Hash{String => String}] canonical ordinal => reason
      def ask(subjects)
        return {} if subjects.empty?

        ordinals = subjects.map { it.feature.ordinal.to_s }
        @out.puts "#{@verb.capitalize} plans [ #{ordinals.join(", ")} ]:"
        subjects.each_with_index.to_h do |subject, index|
          @out.puts "\n#{index + 1}. Plan #{ordinals[index]}: #{subject.feature.title}\n   State: #{subject.status}"
          [ordinals[index], reason]
        end
      end

      private

      # @return [String]
      def reason
        return text("Please provide a reason for #{@verb} this plan:") unless @choices

        picked = @prompt.select("Why are we #{@verb} it today?", @choices, default: @choices.first)
        picked == OTHER ? text("Reason for scrapping this plan:") : picked
      end

      # @param question [String]
      # @return [String] never blank
      def text(question)
        loop do
          answer = @prompt.ask(question).to_s.strip
          return answer unless answer.empty?
        end
      end
    end
  end
end

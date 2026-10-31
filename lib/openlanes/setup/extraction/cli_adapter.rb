# frozen_string_literal: true

require "inquirex-llm"

module OpenLanes
  module Setup
    module Extraction
      # An agent CLI the person is signed in to, in place of an API. The
      # prompts and the parsing stay the OpenAI adapter's; only the call differs.
      class CliAdapter < Inquirex::LLM::OpenAIAdapter
        # @param command [#call] takes the prompt, answers with argv
        # @param runner [OpenLanes::Adapters::ProbeRunner]
        # @param label [String] the CLI's name, for errors
        def initialize(command:, runner:, label:)
          super(api_key: "signed-in", model: label)
          @command = command
          @runner = runner
          @label = label
        end

        private

        # @return [String]
        def provider_name = @label

        # A CLI may print a line of its own around the answer, so only the JSON
        # object is kept. The transport's error text is not repeated: it may
        # quote the description.
        #
        # @return [Hash] the response in the shape the parent's parser reads
        # @raise [Inquirex::LLM::Errors::AdapterError] when the CLI fails
        def call_api(system:, user:, **)
          result = @runner.call(*@command.call("#{system}\n\n#{user}"))
          raise Inquirex::LLM::Errors::AdapterError, "#{@label} exited #{result.status.inspect}" unless result.ok?

          { "choices" => [{ "message" => { "content" => result.stdout[/\{.*\}/m].to_s } }] }
        end
      end
    end
  end
end

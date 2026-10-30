# frozen_string_literal: true

module OpenLanes
  module Setup
    module ProjectForm
      # Walks the form to its end on a terminal, one blank line between questions.
      class Driver
        # Said when nothing can read a description, so it is not asked for.
        NO_ROUTE = "No API key, local Ollama or signed-in agent CLI was found, so every question will be asked."

        # @param renderer [OpenLanes::Setup::ProjectForm::Renderer]
        # @param preselection [OpenLanes::Setup::ProjectForm::Preselection]
        # @param terminal [OpenLanes::Setup::ProjectForm::Terminal]
        # @param prefilled [Hash{Symbol => Object}] flags typed, whose steps are not asked
        def initialize(renderer:, preselection:, terminal:, prefilled: {})
          @renderer = renderer
          @preselection = preselection
          @extractor = terminal.extractor
          @out = terminal.out
          @prefilled = prefilled
        end

        # @param engine [Inquirex::Engine]
        # @return [Hash{Symbol => Object}] every answer, the extraction's included
        def call(engine)
          engine.prefill!(@prefilled.merge(no_extraction: @extractor.nil?))
          announce
          asked = false
          until engine.finished?
            next understand(engine) if llm?(engine.current_step)

            @out.puts if asked
            asked = true
            ask(engine)
          end
          engine.answers
        end

        private

        # @return [void]
        def announce
          @out.puts(ProjectForm.wrap(@extractor ? "Your description goes to #{@extractor.label}, and is not saved." : NO_ROUTE))
          @out.puts
        end

        # @return [Boolean]
        def llm?(step) = step.respond_to?(:llm_verb?) && step.llm_verb?

        # @return [void]
        def understand(engine)
          understood = @extractor ? @extractor.call(engine.current_step, engine.answers[:description]) : {}
          @preselection.understand(understood)
          engine.answer(understood)
        end

        # A refused answer is reported, and the loop asks the same question again.
        #
        # @return [void]
        def ask(engine)
          @renderer.collect(engine)
        rescue Inquirex::Errors::ValidationError => e
          @out.puts(e.message)
        end
      end
    end
  end
end

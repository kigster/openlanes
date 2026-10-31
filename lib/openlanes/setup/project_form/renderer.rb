# frozen_string_literal: true

require "inquirex/tty"

module OpenLanes
  module Setup
    module ProjectForm
      # The stock renderer, with what `openlanes init` needs on top: words wrapped
      # to the terminal, what the scan and the description found preselected, and
      # everything on the prompt's stream, because STDOUT is the deliverable.
      class Renderer < Inquirex::TTY::Renderer
        # @param prompt [TTY::Prompt]
        # @param out [IO]
        # @param width [Integer]
        # @param preselect [#call] takes a step id, answers with what to preselect
        def initialize(prompt:, out: $stderr, width: ProjectForm.width, preselect: ->(_id) {})
          super(prompt:)
          @out = out
          @width = width
          @preselect = preselect
        end

        # The stock {#collect} only passes an answer given before going back, so
        # the first time a question is asked its preselection is added here.
        #
        # @param node [Inquirex::Node]
        # @param suggestion [Array, nil]
        # @param default [Object, nil]
        # @return [Object, nil]
        def render(node, suggestion: nil, default: nil)
          picked = default.nil? ? preselected(node) : default
          super(WrappedNode.new(node, @width), suggestion:, default: picked)
        end

        private

        # @return [Object, nil]
        def preselected(node)
          value = @preselect.call(node.id)
          value.nil? ? node.default : value
        end

        # The stock hints are one fixed line each, which a narrow screen breaks.
        #
        # @return [void]
        def puts(*lines) = lines.empty? ? @out.puts : lines.each { @out.puts(ProjectForm.wrap(it.to_s, @width)) }

        # Enter with nothing chosen is an answer here: nothing is known yet.
        #
        # @return [Array<String>]
        def render_multi_select(node)
          puts pastel.dim("Space selects, Enter moves on.")
          echoed node, prompt.multi_select(node.question, select_options(node), **list_options(node), **multi_select_defaults(node))
        end

        # @return [String]
        def render_select(node)
          echoed node, prompt.select(node.question, select_options(node), **list_options(node), **choice_default(node))
        end

        # The widgets' own help and final echo join the question's last line, which
        # runs it past the width, so neither is drawn; {#echoed} draws the question
        # and the answer again on lines of their own. Every choice is on the screen,
        # so nothing preselected hides on a later page.
        #
        # @return [Hash{Symbol => Object}]
        def list_options(node) = { per_page: node.options.size, show_help: :never, quiet: true }

        # @param node [OpenLanes::Setup::ProjectForm::WrappedNode]
        # @param picked [String, Array<String>]
        # @return [String, Array<String>] the same answer
        def echoed(node, picked)
          words = Array(picked).map { it.to_s.tr("_", " ") }.join(", ")
          puts node.question
          puts pastel.dim("→ #{words.empty? ? "nothing yet" : words}")
          picked
        end

        # The stock rule is always 80 wide, which a narrow screen breaks.
        #
        # @return [void]
        def sep(color = :yellow, char = "━") = puts(pastel.public_send(color, char * @width))
      end
    end
  end
end

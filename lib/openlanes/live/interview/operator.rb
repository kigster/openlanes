# frozen_string_literal: true

require "json"

module OpenLanes
  module Live
    class Interview
      # The unblocker answering in an interview (plan 068): one `claude -p`
      # per turn, running the unblocker's own profile with an interview
      # {Brief}. What it says is JSON turns, each checked by {Turn.check}; a
      # reply that fails the check goes back to the model once to be said
      # again, and is never shown to the person as a refusal.
      class Operator
        # The agent whose profile and prompt the interview runs under.
        NAME = "unblocker"

        # Files of the plan the unblocker reads beside the question.
        DOCUMENTS = %w[spec.md plan.md].freeze

        # Read-only tools: the brief carries what it needs, and nothing it may write.
        TOOLS = %w[Read Grep Glob].freeze

        # Asked when the model could not say a turn the page can draw: a
        # clarifying question, never a refusal.
        FALLBACK = "Could you tell me a little more about what you would like here?"

        # @param root [String] the checkout `claude` runs in
        # @param plans_dir [String]
        # @param agent [OpenLanes::Agents::Agent, nil]
        # @param spawn [Proc] `argv, chdir:, env:` → {Execution::Child}; the suite's seam
        def initialize(root:, plans_dir:, agent: Agents.find(NAME), spawn: Execution::Child.method(:spawn))
          raise OpenLanes::Error, "no agent definition named #{NAME}" unless agent

          @root = File.expand_path(root)
          @plans_dir = plans_dir
          @agent = agent
          @spawn = spawn
        end

        # @param interview [OpenLanes::Live::Interview]
        # @return [Array<OpenLanes::Live::Interview::Turn>] the unblocker's next turns
        def call(interview)
          path = Plans.tree(@plans_dir).find(Plans::Ordinal.parse(interview.plan))&.feature&.path or
            raise OpenLanes::Error, "there is no plan #{interview.plan}"
          brief = { question: question(path, interview.number), history: interview.history, documents: documents(path) }
          turns(interview, Brief.new(**brief).to_s)
        rescue Invalid, JSON::ParserError => e
          turns(interview, Brief.new(**brief, rephrase: e.message).to_s, again: false)
        end

        private

        # @return [Array<OpenLanes::Live::Interview::Turn>]
        def turns(interview, prompt, again: true)
          data = JSON.parse(json_in(ask(prompt)))
          first = interview.history.size + 1
          Array(data["turns"]).each_with_index.map { |raw, i| Turn.parse(raw.merge("id" => "u#{first + i}", "from" => "unblocker")) }
                              .tap { raise Invalid, "the reply held no turns" if it.empty? }
        rescue Invalid, JSON::ParserError
          raise if again

          [Turn.new(id: interview.next_id, from: "unblocker", kind: "text", text: FALLBACK)]
        end

        # @return [String] the JSON object inside +text+, fenced or not
        def json_in(text) = text[/\{.*\}/m] || text

        # @return [String] what the model said
        def ask(prompt)
          command = argv(prompt)
          transcript = profile.adapter.transcript(trace: File::NULL, argv: command)
          child = @spawn.call(command, chdir: @root, env: profile.adapter.environment)
          child.each_chunk { transcript.push(it) }
          child.wait
          transcript.finish
          transcript.result.to_s
        end

        # @return [Array<String>] one turn's `claude -p`, read-only
        def argv(prompt)
          profile.adapter.argv(Adapters::Invocation.new(prompt:,
            root: @root,
            model: profile.model,
            effort: profile.effort,
            denied_tools: Copilot::Operator::WRITE_TOOLS,
            brief: false,
            tools: TOOLS,
            system: @agent.prompt))
        end

        # @return [OpenLanes::Agents::Profile]
        def profile = @profile ||= Agents::Profile.resolve(@agent)

        # @return [String] the question's own section of blocked.md
        def question(path, number)
          text = File.read(File.join(path, "blocked.md"))
          text[/^## B#{number}\b.*?(?=^## |\z)/m] or raise OpenLanes::Error, "the plan asks no such question"
        end

        # @return [Hash{String => String}]
        def documents(path)
          DOCUMENTS.to_h { [it, File.join(path, it)] }.select { |_, file| File.file?(file) }.transform_values { File.read(it) }
        end
      end
    end
  end
end

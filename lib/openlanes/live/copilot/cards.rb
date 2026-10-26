# frozen_string_literal: true

require "json"

module OpenLanes
  module Live
    class Copilot
      # How what copilot wrote becomes the turns the page draws.
      #
      # The agent writes prose, and wherever it wants the page to draw a card
      # it writes one fenced block whose info string is `copilot`, holding one
      # JSON object:
      #
      #   ```copilot
      #   {"card": "confirm", "text": "backend-coder has not moved in 20 minutes.",
      #    "command": {"kind": "stop", "plan": "002", "agent": "backend-coder"},
      #    "confirm": "Stop backend-coder", "done": "backend-coder was asked to stop"}
      #   ```
      #
      #   ```copilot
      #   {"card": "draft", "question": "002/B1", "draft": "Ninety days.", "text": "A draft:"}
      #   ```
      #
      # The agent proposes; this module decides. A card is drawn only when
      # every check passes: the JSON parses, the card is one of the two kinds,
      # a confirm card's command is one of {CONFIRMABLE} and one the command
      # gate itself would take ({Command.parse}, W13), and what it names is on
      # this node's board. Anything else comes back as plain text with the
      # reason, so a card the agent got wrong is something the person reads,
      # never something the page can send. Nothing here sends anything: even a
      # good card only reaches the engine when the person presses its button.
      module Cards
        # A card: a fence opened with exactly `copilot` and closed on a line of its
        # own. An unclosed one does not match, and so stays prose.
        FENCE = /^```#{Agents::Names::COPILOT}[ \t]*\r?\n(.*?)^```[ \t]*$/m

        # The commands a confirm card may carry: W17's "stop, discard and stop
        # run", the ones that cannot be undone and so wait for a person.
        # Message and hold are left out on purpose: the engine files a
        # `message` in the plan's mailbox as from `human`, and a card the
        # person confirms without reading would put the copilot's words there
        # under the person's name.
        CONFIRMABLE = %w[stop discard stop_all].freeze

        # Cards one answer may offer. More is a model listing every action it
        # can think of, and a wall of red buttons is not a question.
        MAX = 3

        # Characters a confirm button's label may hold.
        LABEL = 60

        # Characters the line a confirm card shows once accepted may hold.
        DONE = 200

        # Characters one prose turn keeps. A model that pastes a whole
        # transcript back is cut here rather than sent to every open page.
        PROSE = 20_000

        # A question's id, as the board writes it: `<ordinal>/B<n>`.
        QUESTION = %r{\A[0-9]{3}(?:\.[0-9]{2})?/B[1-9][0-9]*\z}

        # What an answer with nothing in it reads as.
        SILENT = "#{Agents::Names::COPILOT} finished without saying anything.".freeze

        module_function

        # @param answer [String, nil] the agent's final message
        # @param id [String] the person's message id; the turns are `<id>.1`, `<id>.2`, …
        # @param usage [Hash, nil] `{model, up, down}`, carried by every turn
        # @param board [Hash, nil] this node's `Snapshot` as parsed JSON; nil
        #   when no engine is publishing one, and then no card names anything
        # @return [Array<OpenLanes::Live::Copilot::Turn>]
        def turns(answer, id:, usage: nil, board: nil)
          offered = 0
          said = pieces(answer.to_s).filter_map do |kind, body|
            next prose(body) if kind == :prose

            offered += 1
            offered > MAX ? refused(body, "an answer offers at most #{MAX} cards") : card(body, board)
          end
          said = [{ kind: "text", text: SILENT }] if said.empty?
          said.each_with_index.map do |piece, index|
            Turn.new(id: "#{id}.#{index + 1}", from: "copilot", usage:, fields: {}, **piece)
          end
        end

        # The answer cut into prose and card bodies, in the order written.
        #
        # @param answer [String]
        # @return [Array<Array(Symbol, String)>]
        def pieces(answer)
          found = []
          at = 0
          while (match = FENCE.match(answer, at))
            found << [:prose, answer[at...match.begin(0)]] << [:card, match[1]]
            at = match.end(0)
          end
          found << [:prose, answer[at..]]
        end

        # @param body [String]
        # @return [Hash, nil] nil for whitespace between cards
        def prose(body)
          text = body.strip
          return nil if text.empty?

          { kind: "text", text: text.length > PROSE ? "#{text[0, PROSE]}…" : text }
        end

        # @param body [String] the JSON between the fences
        # @param board [Hash, nil]
        # @return [Hash] a card, or the text it degrades to
        def card(body, board)
          data = JSON.parse(body)
          raise Invalid, "a card is one JSON object" unless data.is_a?(Hash)

          data = data.transform_keys(&:to_s)
          case data["card"]
          when "confirm" then confirm(data, board)
          when "draft" then draft(data, board)
          else raise Invalid, "#{data["card"].inspect} is not a card; there are confirm and draft"
          end
        rescue JSON::ParserError
          refused(body, "it is not JSON")
        rescue Invalid, Command::Invalid => e
          refused(body, e.message)
        end

        # @param data [Hash]
        # @param board [Hash, nil]
        # @return [Hash]
        # @raise [OpenLanes::Live::Copilot::Invalid, OpenLanes::Live::Command::Invalid]
        def confirm(data, board)
          raw = data["command"]
          raise Invalid, "a confirm card needs a command object" unless raw.is_a?(Hash)

          raw = raw.transform_keys(&:to_s)
          kind = raw["kind"].to_s
          raise Invalid, "#{kind.inspect} is not a command #{Agents::Names::COPILOT} may offer; it offers #{CONFIRMABLE.join(", ")}" unless CONFIRMABLE.include?(kind)

          # The payload is dropped: none of these kinds reads one, and a card
          # carries exactly what its button says and nothing the person cannot see.
          command = Command.parse(raw.slice("kind", "plan", "agent").merge("id" => "card", "payload" => {}))
          on_board!(command, board)
          { kind:   "confirm",
            text:   words(data["text"], LIMIT) || "This needs you to confirm it.",
            fields: { "command" => command.wire.except(:id).transform_keys(&:to_s),
                      "confirm" => words(data["confirm"], LABEL) || raise(Invalid, "a confirm card needs its button's label"),
                      "done"    => words(data["done"], DONE) || raise(Invalid, "a confirm card needs what it says once done") } }
        end

        # @param data [Hash]
        # @param board [Hash, nil]
        # @return [Hash]
        # @raise [OpenLanes::Live::Copilot::Invalid]
        def draft(data, board)
          question = data["question"].to_s
          raise Invalid, "#{question.inspect} is not a question id like 002/B1" unless question.match?(QUESTION)

          # The board writes ids in full (`002.00/B1`); the agent may write `002/B1`.
          plan, number = question.split("/")
          question = "#{ordinal(plan)}/#{number}"
          raise Invalid, "no question #{question} is waiting on this board" unless questions(board).include?(question)

          draft = words(data["draft"], LIMIT) or raise Invalid, "a draft card needs the draft"
          { kind: "draft", text: words(data["text"], LIMIT) || "A draft answer to #{question}.",
            fields: { "question" => question, "draft" => draft } }
        end

        # The engine refuses a command for a plan or a car it does not have,
        # but only once the person has pressed the button. Checking here keeps
        # a card for something that is not running off the page altogether.
        #
        # @param command [OpenLanes::Live::Command]
        # @param board [Hash, nil]
        # @return [void]
        # @raise [OpenLanes::Live::Copilot::Invalid]
        def on_board!(command, board)
          raise Invalid, "no run is publishing a board here, so there is nothing to act on" if board.nil?
          return unless Command::PLAN_KINDS.include?(command.kind)

          plan = Array(board["plans"]).find { ordinal(it["ordinal"]) == ordinal(command.plan) }
          raise Invalid, "plan #{command.plan} is not on this board" unless plan
          return unless Command::AGENT_KINDS.include?(command.kind)
          return if Array(plan["cars"]).any? { it["agent"] == command.agent }

          raise Invalid, "#{command.agent} is not working #{command.plan}"
        end

        # @param board [Hash, nil]
        # @return [Array<String>] every question id waiting on the board
        def questions(board) = Array(board&.dig("plans")).flat_map { Array(it["questions"]) }.map { it["id"].to_s }

        # @param value [Object]
        # @return [String, nil]
        def ordinal(value) = Plans::Ordinal.parse(value.to_s)&.to_s || value.to_s

        # @param value [Object]
        # @param limit [Integer]
        # @return [String, nil] stripped, nil when empty
        # @raise [OpenLanes::Live::Copilot::Invalid] when longer than +limit+
        def words(value, limit)
          return nil unless value.is_a?(String)

          text = value.strip
          return nil if text.empty?
          raise Invalid, "#{text[0, 24].inspect}… is longer than #{limit} characters" if text.length > limit

          text
        end

        # What a card the gate would not take becomes: its body as text, with
        # the reason, so the person sees what was meant and nothing is sent.
        #
        # @param body [String]
        # @param reason [String]
        # @return [Hash]
        def refused(body, reason)
          { kind: "text",
            text: "I wrote a card the control room does not accept (#{reason}), so nothing was offered. " \
                  "What I wrote:\n\n#{body.strip[0, PROSE]}" }
        end
      end
    end
  end
end

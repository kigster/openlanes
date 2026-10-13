# frozen_string_literal: true

require "shellwords"

module OpenLanes
  module Execution
    # What one agent is told on one plan: its own definition, then the facts
    # of this invocation, the ledger it signs, its budgets, its control file,
    # its partner's mailbox and the boundary it works inside.
    #
    # Built here rather than in {Executor} so that starting a process and
    # deciding what to say to it are two jobs in two places. Every number in
    # it (seconds, tokens, the commands withheld) is handed in by the
    # executor that enforces it, so the prompt and the enforcement cannot
    # disagree.
    class Prompt
      # This checkout's own executable, named in every command the agent is
      # told to run. A bare `openlanes` resolves through the agent's PATH to
      # whatever release is installed, which can predate `state sign`.
      EXECUTABLE = File.expand_path("../../../exe/openlanes", __dir__)

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @param root [String] the checkout the agent works in
      # @param profile [OpenLanes::Agents::Profile]
      # @param round [Integer]
      # @param successor [String, nil] who the agent names on its `next:`
      # @param partners [Array<OpenLanes::Agents::Agent>]
      # @param control [String, nil] the control file, when there is one
      # @param instructions [String] what `run --prompt` typed
      # @param max_tokens [Integer, nil] the enforced token budget
      # @param seconds [Integer, nil] the enforced clock
      # @param denied [Array<String>] commands withheld
      # @param granted [Array<String>] commands lifted for this agent
      def initialize(agent:, subject:, root:, profile:, round: 1, successor: nil, partners: [], control: nil,
        instructions: "", max_tokens: nil, fresh_budget: false, seconds: nil, denied: [], granted: [])
        @agent = agent
        @subject = subject
        @root = root
        @profile = profile
        @round = round
        @successor = successor
        @partners = partners
        @control = control
        @instructions = instructions.to_s.strip
        @max_tokens = max_tokens
        @fresh_budget = fresh_budget
        @seconds = seconds
        @denied = denied
        @granted = granted
      end

      # @return [String]
      def to_s
        <<~PROMPT
          #{agent.prompt}

          ---

          ## This invocation

          Plan folder    : #{subject.feature.path}
          Plan number    : #{subject.feature.ordinal}
          Current state  : #{subject.status.emoji} #{subject.status.label}
          Repository root: #{root}

          #{"The folder's name is not currently justified: #{subject.violation}" if subject.violation}
          #{operator_instructions}#{requirements_section}#{completion_section}#{suggestions_section}#{ledger_section(agent, subject, round:, successor:)}#{budget_section}#{time_budget_section(agent)}#{control_section(control, agent, subject)}#{questions_section}#{mailbox_section(agent, subject, partners)}
          ## Boundary — enforced, not requested

          You may read anything, and write source, tests and the plan's own
          markdown.

          #{withheld_preamble(profile)}

          #{@denied.map { |c| "  #{c}" }.join("\n")}
          #{granted_section}
          The harness checks afterwards that HEAD has not moved, and a round that
          moved it is reported as a failure and rolled into the report. A prompt
          is a request; a check is a guarantee.

          Claim each directory or file before you write it, and release it when
          that write is done. Name yourself on every call, since `alock` would
          otherwise sign with a fingerprint your sub-agents share; give each
          sub-agent its own suffix, e.g. `AGENT_ID=#{agent.name}-schema`:

              AGENT_ID=#{agent.name} alock acquire <path> "<why>"
              AGENT_ID=#{agent.name} alock release <path>

          A refused `acquire` means another agent holds it: work on something
          else, never write it anyway. Before your closing signature, run
          `AGENT_ID=#{agent.name} alock release-all`.
        PROMPT
      end

      # What a compacted agent is told when its session is resumed (W28). Its
      # own instructions survive in the compacted summary; what it needs is
      # to know that the INTERRUPT it just obeyed is over, and that the
      # session it is in is the same one.
      #
      # @return [String]
      def continuation
        plans_dir = File.dirname(subject.feature.path)
        <<~PROMPT
          Your context was just compacted at a person's request. This is the same
          session and the same round on plan #{subject.feature.ordinal}.

          The INTERRUPT you were sent was only to pause you for the compaction.
          It is over: do not end your turn because of it. Read your RESUME note,

              #{cli} mail read --dir "#{plans_dir}" --plan #{subject.feature.ordinal} --for #{agent.name}

          then carry on from its exact next step, as your original instructions
          say, and sign your ledger when the work is done, as before. If you had
          already finished and signed Completed, end your turn now.

          #{"Your control file is still #{control}, now empty. Keep polling it between steps." if control}
        PROMPT
      end

      private

      attr_reader :agent, :subject, :root, :profile, :round, :successor, :partners, :control

      # Only a CLI that actually refuses the commands may be described as
      # refusing them.
      #
      # @param profile [OpenLanes::Agents::Profile]
      # @return [String]
      def withheld_preamble(profile)
        if profile.adapter.enforces_tool_denial?
          "These are withheld from you, not merely discouraged — `#{profile.adapter.executable}` is\n" \
            "invoked with them disallowed:"
        else
          "You must not run these. `#{profile.adapter.executable}` cannot withhold them, so the\n" \
            "check below is what catches a run that does:"
        end
      end

      # The one paragraph every agent gets, identically, about the ledger. It
      # lives here rather than in seven definition files so the wording cannot
      # drift between agents, and so the names, the round and the successor are
      # the harness's facts rather than the agent's guesses.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @param round [Integer]
      # @param successor [String, nil]
      # @return [String]
      def ledger_section(agent, subject, round:, successor:)
        sign = "#{cli} state sign --dir \"#{File.dirname(subject.feature.path)}\" --plan #{subject.feature.ordinal} " \
               "--agent #{agent.name} --round #{round}"
        handoff = successor ? " --next #{successor}" : ""
        <<~SECTION

          ## The ledger - sign at the start and at the end

          You sign this plan's `state.json`, through the command below. Never
          edit `state.json` by hand: the command takes a lock, so you and an
          agent working beside you cannot overwrite each other. Run it by the
          path given, not as a bare `openlanes`: the one on your PATH may be an
          older release without these commands, and wherever your instructions
          say `openlanes`, they mean `#{cli}`. Before you do any work:

              #{sign} --status Started

          When you finish:

              #{sign} --status Completed#{handoff}

          Sign `Completed` only if your assignment is genuinely done. Otherwise
          use `--status "Almost completed"`, `Interrupted` or `Blocked`, with no
          `--next`. Where your instructions say to sign `Blocked, round N
          (technical)` or `Completed, round N (approved)`, pass the words in
          parentheses as `--note technical` or `--note approved`. The harness
          renames the plan folder and starts the next agent from these
          signatures; you never rename the folder yourself.
        SECTION
      end

      # The section `run --max-tokens` adds. Stating the number is what lets
      # the agent finish before it, rather than discovering the cap by dying
      # on it with half a file written.
      #
      # @return [String]
      def budget_section
        return "" unless @max_tokens&.positive?

        "\n## Token budget — #{@max_tokens} tokens, enforced\n\n" \
          "This invocation is aborted once its total spend (#{spend}, " \
          "sub-agents included) crosses #{@max_tokens} tokens. Budget the work: " \
          "plan what fits, write results to disk as you go, and finish — or " \
          "write a handoff note into the plan folder — before the meter runs " \
          "out. Anything unwritten at the cap is lost.\n"
      end

      # @return [String] the executable, quoted for a shell
      def cli = Shellwords.escape(EXECUTABLE)

      # @return [String] what the budget counts
      def spend = @fresh_budget ? "new input plus output; cache reads are free" : "input plus output"

      # The section describing the advisory clock this invocation runs against,
      # stated in the prompt so an agent can pace itself. The number is
      # whatever {#timeout_for} will actually enforce, so the prompt and the
      # clock can never disagree — an agent whose prose names its own figure
      # goes stale the first time someone passes `--timeout`, and stale is
      # worse than silent.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @return [String]
      def time_budget_section(agent)
        seconds = @seconds
        return "" unless seconds&.positive?

        minutes = (seconds / 60.0).round
        "\n## Time budget - #{seconds} seconds\n\n" \
          "You have about #{minutes} minute#{"s" unless minutes == 1} of wall clock. The control " \
          "file below tells you how it is going: `WARN: 10 minutes left`, `WARN: 5 minutes left`, " \
          "`WRAP_UP: 1 minute left, write to disk now`, then `STOP`. Sixty seconds after STOP " \
          "the process is killed, and anything unwritten is lost. Write each result to disk as " \
          "you reach it, and sign your closing ledger entry before anything else once you see " \
          "WRAP_UP.#{concurrency_advice(agent)}\n"
      end

      # Only worth saying to an agent that can actually do it. Telling an agent
      # without `Task` to parallelise is telling it to feel bad about a tool it
      # was not given.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @return [String]
      def concurrency_advice(agent)
        return "" unless agent.allowed_tools.include?("Task")

        " Where the work divides into parts that do not read each other's output, run them " \
          "as one wave of concurrent sub-agents rather than in series: the wave costs one " \
          "part's wall clock, and the series costs the sum of all of them."
      end

      # Two agents on one plan are two processes. Naming the partner and the
      # exact commands is what replaced guessing the partner's session from
      # every Claude session on the machine.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @param partners [Array<OpenLanes::Agents::Agent>]
      # @return [String]
      def mailbox_section(agent, subject, partners)
        return "" if partners.empty?

        plans_dir = File.dirname(subject.feature.path)
        plan = subject.feature.ordinal
        names = partners.map { |p| "`#{p.name}`" }
        who = names.size == 1 ? "Your partner on this plan is #{names.first}" : "Your partners on this plan are #{names.join(" and ")}"

        <<~SECTION

          ## Mailbox - poll it between steps

          #{who}. You share one worktree and one branch, but not a process, so
          the only way to reach each other is the plan's mailbox, kept in the
          plan's `state.json`. Use the commands; never edit the file by hand.

          Read it before each significant step and whenever you finish a unit:

              #{cli} mail read --dir "#{plans_dir}" --plan #{plan} --for #{agent.name}

          Pass `--after N`, with the number of the last message you have read,
          to see only what is new. Write to it when you land an interface your
          partner is waiting on, when you amend the contract, when you need
          something from their half, and when you finish:

              #{cli} mail send --dir "#{plans_dir}" --plan #{plan} --from #{agent.name} --to #{partners.first.name} "what you need them to know"

          Every message is appended with a number and a timestamp and never
          edited, so a person can read the exchange after the round. A question
          your partner has not answered within a few steps is not a reason to
          stop: write your assumption into implementation-plan.md and carry on.
        SECTION
      end

      # The section a control file adds. Present on every invocation, because
      # the advisory clock writes into it whether or not anyone is watching.
      #
      # INTERRUPT is what makes a restart after Ctrl-C safe: the agent that
      # was cut off leaves a mailbox note to whoever picks the plan up, and
      # every agent is told to read its mail first, so the next run resumes
      # from the note rather than redoing work already on disk.
      #
      # @param control [String, nil]
      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def control_section(control, agent, subject)
        return "" if control.nil?

        plans_dir = File.dirname(subject.feature.path)
        plan = subject.feature.ordinal
        <<~SECTION

          ## Control file — poll it between steps

              #{control}

          Read this file before each significant step. Empty means carry on.
          A line starting WARN: tells you how much time is left. WRAP_UP: means
          finish the essential remainder now. STOP means write what you have,
          sign your ledger entry, and end your turn.

          HOLD means a person wants to say something to you. Finish the write
          you are in, then read your mail and wait for their next message
          before you do anything else; check every thirty seconds:

              #{cli} mail read --dir "#{plans_dir}" --plan #{plan} --for #{agent.name}

          INTERRUPT means the operator pressed Ctrl-C and the run will be started
          again later. Start nothing new. Finish the write you are in the middle
          of, so no file is left half-written, then leave a resume note for
          whoever runs next — most likely you — saying what is done, what is
          not, and the exact next step:

              #{cli} mail send --dir "#{plans_dir}" --plan #{plan} --from #{agent.name} --to #{agent.name} "RESUME: ..."

          Then sign `--status Interrupted`, with no `--next`, and
          end your turn.

          Before you start, check for such a note from an earlier run:

              #{cli} mail read --dir "#{plans_dir}" --plan #{plan} --for #{agent.name}

          If there is a RESUME note, continue from it and do not redo what it
          says is done; check the files it names rather than taking it on trust.
        SECTION
      end

      # How to mark a yes/no question in `blocked.md` (W30). The page offers
      # Yes and No buttons for exactly the questions marked this way and never
      # guesses from the wording, so an agent that does not mark one gets a
      # text box, and one that marks a two-way choice gets a meaningless yes.
      # Said once here, for every agent that writes `blocked.md`, rather than
      # in each definition, so the marker cannot drift between them.
      #
      # @return [String] empty for an agent whose definition never mentions
      #   `blocked.md`, and for the agent that drains it
      def questions_section
        return "" unless agent.prompt.include?("blocked.md") && !agent.handles.include?(:blocked)

        <<~SECTION

          ## Questions in blocked.md: yes/no questions

          When a question can be answered with a plain yes or no, ask it that
          way and mark it, on its own line straight under its heading:

              ## B2 Rebase onto main
              #{Live::Snapshot::YES_NO_MARK}

              The pull request conflicts in lib/openlanes/cli.rb. Should I rebase onto main?

          The person answers with a button, and the answer reaches you as the
          bare word `yes` or `no`, so branch on the word. Mark only a real yes/no
          question: "Should I start it, or skip the integration specs?" is a
          choice between two things, and needs words.
        SECTION
      end

      # How the spec's author says the task is finished, and how to tell. The
      # harness copies both into plan.md after the planner signs; saying so
      # here keeps a planner from burying them in a paraphrase, and gives the
      # builder and the reviewer the same two lists to hold the work to.
      #
      # @return [String] empty when the spec says neither
      def completion_section
        spec = Plans::Spec.for(subject)
        return "" if spec.completed_when.empty? && spec.how_to_verify.empty?

        lists = [["The task is finished when", spec.completed_when], ["How to verify it", spec.how_to_verify]]
        body = lists.reject { |_, items| items.empty? }.map do |title, items|
          "#{title}:\n\n#{items.map { |item| "- #{item}" }.join("\n")}\n"
        end

        "\n## Completion criteria — from the spec's author\n\n" \
          "Do not sign Completed until the first list holds, and run each check in the second. " \
          "If you write plan.md, copy both lists into it verbatim, under `## Task completed when` and " \
          "`## How to verify`; the harness adds them if you do not. A reviewer rejects work that fails a check.\n\n" \
          "#{body.join("\n")}"
      end

      # What the spec's author requires, if they said. The opposite of
      # {#suggestions_section}: an agent that weighs a requirement against its
      # own taste will sometimes decide against it, so this states that there
      # is nothing to weigh, and gives it the one honest way out, which is to
      # stop and say so. A reviewer is told to hold the work to them.
      #
      # {Checks} appends the one requirement no spec states: the suite and the
      # linters pass. It goes last, after the author's own.
      #
      # @return [String] empty when the spec requires nothing and the agent
      #   changes no code
      def requirements_section
        requirements = Plans::Spec.for(subject).requirements
        requirements += [Checks.requirement(root)] if Checks.apply_to?(agent)
        return "" if requirements.empty?

        "\n## Implementation requirements\n\n" \
          "These are requirements, not suggestions. Do exactly what each one says; do not substitute, " \
          "weaken or reinterpret one, and do not decide you know better. If you cannot meet one, stop " \
          "and sign Blocked with `--note technical`, and write which requirement and why in the " \
          "document you own. A reviewer rejects work that does not meet them.\n\n" \
          "#{requirements.map { |item| "- #{item}" }.join("\n")}\n"
      end

      # What the spec's author would build it with, if they said. Labelled as
      # a suggestion in so many words, because an agent handed a language and
      # a library list as an order will follow it into a dead end rather than
      # say the route is wrong; handed as advice, it can take a better one and
      # write the reason in the document it owns. The signature note is
      # read by the harness for keywords, so it is no place for prose.
      #
      # @return [String] empty when the spec suggests nothing
      def suggestions_section
        suggestions = Plans::Spec.for(subject).suggestions
        return "" if suggestions.empty?

        "\n## Implementation suggestions — from the spec's author\n\n" \
          "These are suggestions, not requirements: a language, libraries, an approach the author " \
          "had in mind. Prefer them when they fit. If you find a better route, take it and write why " \
          "in the document you own, not in the signature note.\n\n#{suggestions.map { |item| "- #{item}" }.join("\n")}\n"
      end

      # The section `run --prompt` adds, labelled as coming from the person who
      # started the run so the agent can tell a one-off steer from its own
      # standing definition.
      #
      # @return [String]
      def operator_instructions
        return "" if @instructions.empty?

        "\n## Operator instructions — this invocation only\n\n#{@instructions}\n"
      end

      # Spelled out in the prompt as well as withheld at the tool layer, because
      # an agent that does not know it has been granted something does not use
      # it — and `hansolo-reviewer` silently never approving anything looks
      # exactly like `hansolo-reviewer` approving nothing worth approving.
      #
      # @return [String]
      def granted_section
        return "" if @granted.empty?

        "\nYou may run these, which most agents may not:\n\n#{@granted.map { |c| "  #{c}" }.join("\n")}\n"
      end
    end
  end
end

# frozen_string_literal: true

require "securerandom"

module OpenLanes
  module Adapters
    # `grok -p`, streaming JSON (grok CLI 1.0.46).
    #
    # Grok refuses a denied command itself: `--deny "Bash(git push*)"` turns
    # the call into a failed tool result ("Denied by permission policy"), so
    # the prompt can say the guard is real. It has no flag that leaves the
    # operator's own MCP servers and plugins behind, so a lean run is the
    # same as any other.
    class Grok < Base
      # Grok says `xhigh` for the top of its scale and has no `max`.
      EFFORT = { "low" => "low", "medium" => "medium", "high" => "high", "xhigh" => "xhigh", "max" => "xhigh" }.freeze

      # Built-in tools no agent here gets: three that wait on a person nobody
      # under `-p` can answer, one that outlives the run, and one that sends
      # feedback to xAI beyond the conversation itself.
      UNATTENDED = %w[ask_user_question enter_plan_mode exit_plan_mode scheduler_create send_feedback].freeze

      # `-r <id>` carries a session on, and `grok -p "/compact" -r <id>`
      # compacts it headless, printing `auto_compact_completed` (recorded
      # 2026-10-28). It refuses denied commands, but nothing here holds an
      # agent to a fixed tool set and its own files, so a confined agent is
      # not run on it.
      CAPABILITIES = Capabilities.new(compacts: true,
        resumes: true,
        enforces_tool_denial: true,
        confines: false,
        compact_prompt: "/compact")

      # The first line `grok models` prints when signed in. Its exit code is 0
      # either way.
      SIGNED_IN = /\AYou are logged in/

      # One model in `grok models`: `  * grok-4.7 (default)` or `  - grok-4.6`.
      LISTED = /\A\s+[*-]\s+(\S+)/

      # The flags that name a session. Placed before the prompt, so the first
      # one in an argv is always this adapter's.
      SESSION_FLAGS = %w[-r -s].freeze

      # @return [OpenLanes::Adapters::Capabilities]
      def capabilities = CAPABILITIES

      # A fresh session gets an id of the harness's choosing (`-s`), because
      # grok names its session only in the `end` event, and an agent stopped
      # to be compacted never prints one.
      #
      # @param invocation [OpenLanes::Adapters::Invocation]
      # @return [Array<String>]
      def argv(invocation)
        argv = ["grok", *session(invocation), "-p", invocation.prompt,
                "--output-format", "streaming-json", "--cwd", invocation.root, "--always-approve"]
        argv += ["-m", invocation.model] if invocation.model
        effort = effort(invocation.effort)
        argv += ["--reasoning-effort", effort] if effort
        invocation.denied_commands.each { argv += ["--deny", "Bash(#{it}*)"] }
        argv += ["--disallowed-tools", UNATTENDED.join(",")]
        argv << "--disable-web-search" unless invocation.network
        argv
      end

      # Plan mode, with nothing fetched from the web.
      #
      # @param prompt [String]
      # @param model [String, nil]
      # @return [Array<String>]
      def question_argv(prompt, model: nil)
        ["grok", "-p", prompt, "--permission-mode", "plan", "--disable-web-search", *(model ? ["-m", model] : [])]
      end

      # @param effort [String, nil]
      # @return [String, nil]
      def effort(effort) = effort && EFFORT[effort.to_s]

      # @param trace [String, nil]
      # @param argv [Array<String>] the command whose output this reads, for
      #   the session it names
      # @return [OpenLanes::Adapters::Grok::Stream]
      def transcript(trace: nil, argv: [], **, &)
        flag = argv.index { SESSION_FLAGS.include?(it) }
        Stream.new(trace:, session: flag && argv[flag + 1], &)
      end

      private

      # @param invocation [OpenLanes::Adapters::Invocation]
      # @return [Array<String>]
      def session(invocation) = invocation.resume ? ["-r", invocation.resume] : ["-s", SecureRandom.uuid]

      # `grok models`: whether signed in on its first line, then the models,
      # the default marked `*`.
      #
      # @param runner [OpenLanes::Adapters::ProbeRunner]
      # @param at [Time]
      # @return [OpenLanes::Adapters::Availability]
      def check(runner, at)
        result = runner.call("grok", "models")
        return timed_out(result, at) if result.timed_out?
        return Availability.down(name, "not signed in (run `grok login`)", at) unless result.stdout.match?(SIGNED_IN)

        models = result.stdout.lines.filter_map { it[LISTED, 1] }.map { Model.new(id: it, label: it) }
        Availability.up(name, models, at)
      end
    end
  end
end

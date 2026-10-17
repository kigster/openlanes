# frozen_string_literal: true

module OpenLanes
  module Engine
    module Verification
      # The plan's app, up for exactly as long as chewie runs (M1, M12):
      # started in the plan's checkout through {Apps.supervisor}, and stopped
      # in `ensure`, whatever the agent did, so no verification leaves a dev
      # server holding a port from the shared registry.
      #
      # A project with no `app:` starts nothing and chewie verifies through the
      # shell (M11), which is how openlanes itself, a CLI gem, is verified.
      class AppSession
        # The app did not come up, so chewie is never started: a verifier
        # pointed at a dead port can only report what the engine already
        # knows. The rejection quotes {#tail} (M1: the last 20 lines).
        #
        # @!attribute [r] process
        #   @return [String, nil] the process that failed
        # @!attribute [r] reason
        #   @return [String]
        # @!attribute [r] tail
        #   @return [Array<String>] that process's last lines
        Failed = Data.define(:process, :reason, :tail) do
          # @return [String] the opening of every rejection it causes
          def headline = "the app does not start"

          # @return [String] Markdown, for the report and the comment
          def to_markdown
            first = reason.to_s.lines.first.to_s.strip
            lines = ["#{headline}: #{first}"]
            unless tail.empty?
              lines << "" << "The last #{tail.size} lines #{process || "it"} printed:" << "" << "```text"
              lines.concat(tail) << "```"
            end
            lines.join("\n")
          end
        end

        # @param definition [OpenLanes::Apps::Definition, nil] nil when the
        #   project declares no app
        # @param root [String] the plan's checkout
        # @param plan [String] the ordinal
        # @param branch [String]
        # @param supervisor_factory [#call] keywords to a supervisor; the
        #   suite passes one with its own port registry
        def initialize(definition:, root:, plan:, branch:, supervisor_factory: Apps.method(:supervisor))
          @definition = definition
          @root = root
          @plan = plan
          @branch = branch
          @factory = supervisor_factory
        end

        # @yieldparam statuses [Array<OpenLanes::Apps::Status>] every process,
        #   ready; empty when there is no app
        # @return [Object, Failed] the block's value, or {Failed} without
        #   calling the block
        def around
          return yield([]) if @definition.nil?

          supervisor = @factory.call(definition: @definition, root: @root, plan: @plan, branch: @branch)
          begin
            supervisor.start
          rescue Apps::Supervisor::StartFailed => e
            return Failed.new(process: e.process, reason: e.message, tail: e.process ? supervisor.log_tail(e.process) : [])
          end
          yield supervisor.statuses
        ensure
          supervisor&.stop
        end

        # What chewie is told about the app, written into its round's folder
        # before it starts, so the ports reach it without the prompt (which
        # is the executor's) having to know apps exist.
        #
        # @param statuses [Array<OpenLanes::Apps::Status>]
        # @param definition [OpenLanes::Apps::Definition, nil]
        # @return [String] Markdown
        def self.note(statuses, definition)
          return <<~MARKDOWN if statuses.empty?
            # The app

            This project declares no `app:` in `.openlanes.yml`, so nothing was started.
            Follow `## How to test` through the shell (M11).
          MARKDOWN

          envs = definition.processes.to_h { [it.name, it.port_env] }
          rows = statuses.map { "| #{it.process} | `#{envs[it.process]}=#{it.port}` | #{it.url} | #{"yes" if it.preview} |" }
          <<~MARKDOWN
            # The app

            The engine started every process below, ready, and stops them when you finish.
            Do not start or stop them yourself.

            | Process | Port | URL | Preview |
            | :------ | :--- | :-- | :------ |
            #{rows.join("\n")}
          MARKDOWN
        end
      end
    end
  end
end

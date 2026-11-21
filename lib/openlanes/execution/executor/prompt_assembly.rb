# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # The prompt one invocation is started with: the agent's own, what the
      # run was told (`--prompt`, the token budget), the clock and the grants
      # it runs under, a reviewer's packet, and the project's lessons.
      class PromptAssembly
        # @param options [OpenLanes::Execution::Executor::Options]
        # @param preferences [OpenLanes::Execution::Executor::Preferences] the clock each agent gets
        def initialize(options, preferences)
          @options = options
          @preferences = preferences
          @memory_lock = Mutex.new
        end

        # @param attempt [OpenLanes::Execution::Executor::Attempt] the agent, plan and profile
        # @param request [OpenLanes::Execution::Executor::Request]
        # @return [String]
        def prompt_for(attempt, request)
          agent = attempt.agent
          Prompt.new(**request.to_h,
            agent:,
            subject: attempt.subject,
            profile: attempt.profile,
**told,
**bounds(agent),
            packet: packet_for(agent, attempt.subject, request.rebase),
            memory: lessons_for(agent)).to_s
        end

        # A reviewer's packet for this plan's review round. A dry run fetches
        # nothing, and a reviewer resolving a stopped rebase is not reviewing.
        # A packet that cannot be built costs the reviewer its own fetches,
        # as before plan 060.00, never the round.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @param subject [OpenLanes::Plans::Subject]
        # @param rebase [OpenLanes::Vcs::Refresh::Outcome, nil]
        # @return [String] empty when this invocation gets none
        def packet_for(agent, subject, rebase)
          packets = @options.packets
          return "" if packets.nil? || @options.dry_run || rebase || agent.phase.to_s != "review"

          packets.call(subject).to_s
        rescue Error, SystemCallError => e
          UI.log("no review packet for #{subject.feature.ordinal}: #{e.message}", level: :warn, plan: subject.feature.ordinal.to_s)
          ""
        end

        # One snapshot per run: the reviewed lessons as the default branch held
        # them when the first agent started. Reading the checkout on every
        # invocation let a builder's freshly written lesson reach the reviewer
        # judging that builder (PR 196); a snapshot also means every agent in a
        # run is told the same thing. A lesson merged mid-run waits for the next.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @return [String]
        def lessons_for(agent) = @options.memory ? Memory.section(agent:, library: lessons) : ""

        # The ids {#lessons_for} lists for +agent+, from the same snapshot,
        # so what is counted as offered is what the prompt carried.
        #
        # @param agent [OpenLanes::Agents::Agent]
        # @return [Array<String>] empty under `memory: false`
        def offered_to(agent) = @options.memory ? Memory.offered(agent:, library: lessons) : []

        private

        # @return [OpenLanes::Memory::Library]
        def lessons = @memory_lock.synchronize { @lessons ||= Memory.library(root: @options.root) }

        # @return [Hash{Symbol => Object}] what `run` was told, for every agent alike
        def told = @options.to_h.slice(:instructions, :max_tokens, :fresh_budget)

        # @param agent [OpenLanes::Agents::Agent]
        # @return [Hash{Symbol => Object}] the clock and the grants this agent runs under
        def bounds(agent)
          { seconds: @preferences.timeout_for(agent), denied: Grants.denied_commands(agent), granted: Grants.granted_to(agent) }
        end
      end
    end
  end
end

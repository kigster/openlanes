# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"

module OpenLanes
  module Adapters
    class Gemini < Base
      # What one agent may not do, as a gemini policy file (`--policy`).
      #
      # Gemini has no deny flag; its policy engine is the denylist. A file
      # passed with `--policy` sits in the user tier, above the default tier
      # that holds `--approval-mode yolo`'s allow-all, and a deny on a shell
      # command wins even when it is one part of `a && b`. The file also
      # replaces `~/.gemini/policies`, so the operator's own rules do not
      # reach the agent.
      class Policy
        # The directory every policy is written to: outside the repository,
        # like the traces, so the after-check has nothing new to ignore.
        DIR = File.join(Dir.tmpdir, "openlanes-gemini-policies")

        # Highest priority within the user tier.
        PRIORITY = 999

        # Gemini's shell tool, the only one `commandPrefix` applies to.
        SHELL = "run_shell_command"

        # The tools that reach the internet, withheld unless the agent
        # declares `network: true`.
        NETWORK = %w[google_web_search web_fetch].freeze

        # The tool that waits on a person nobody under `-p` can answer.
        UNATTENDED = %w[ask_user].freeze

        # @param denied_commands [Array<String>] command prefixes, e.g. `git push`
        # @param network [Boolean]
        def initialize(denied_commands:, network:)
          @denied_commands = denied_commands
          @network = network
        end

        # The file, written once per distinct content: its name is the digest
        # of what it says, so two agents with the same denylist share one and
        # an argv can be built twice without writing twice.
        #
        # @return [String] the path to pass to `--policy`
        def path
          text = to_toml
          file = File.join(DIR, "#{Digest::SHA256.hexdigest(text)[0, 16]}.toml")
          return file if File.exist?(file)

          FileUtils.mkdir_p(DIR)
          File.write(file, text)
          file
        end

        # @return [String]
        def to_toml
          rules = [*(shell_rule unless denied_commands.empty?), tools_rule(UNATTENDED + (network ? [] : NETWORK))]
          ["# Written by openlanes: what this agent may not do.\n", *rules].join("\n")
        end

        private

        # @return [Array<String>]
        attr_reader :denied_commands

        # @return [Boolean]
        attr_reader :network

        # @return [String]
        def shell_rule
          rule(SHELL, "commandPrefix = #{list(denied_commands)}", "denyMessage = \"openlanes withholds this command\"")
        end

        # A tool denied outright is taken out of the model's tool list.
        #
        # @param tools [Array<String>]
        # @return [String]
        def tools_rule(tools) = rule(list(tools))

        # @param tool [String] a quoted name or a TOML array of them
        # @return [String]
        def rule(tool, *extra)
          tool = JSON.generate(tool) unless tool.start_with?("[")
          ["[[rule]]", "toolName = #{tool}", *extra, "decision = \"deny\"", "priority = #{PRIORITY}"].join("\n") << "\n"
        end

        # A TOML array of basic strings, which JSON's string escapes satisfy.
        #
        # @param values [Array<String>]
        # @return [String]
        def list(values) = "[#{values.map { JSON.generate(it) }.join(", ")}]"
      end
    end
  end
end

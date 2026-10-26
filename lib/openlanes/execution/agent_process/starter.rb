# frozen_string_literal: true

require "rbconfig"
require "securerandom"

module OpenLanes
  module Execution
    class AgentProcess
      # Starts agents for one project: the executor's spawn seam.
      Starter = Data.define(:dir, :root, :spawner) do
        # @param dir [String]
        # @param root [String]
        # @param spawner [#spawn]
        def initialize(dir:, root:, spawner: Spawner::System) = super

        # @param argv [Array<String>] the agent CLI
        # @param chdir [String] where the CLI runs: the plan's checkout
        # @param env [Hash{String => String}] on top of {Child.environment}
        # @param label [Label]
        # @return [AgentProcess]
        def call(argv, chdir:, label:, env: {})
          files = files_for(label)
          FileUtils.mkdir_p(dir)
          File.write(files.output, "")
          pid = spawner.spawn(Child.environment.merge(env), *command(argv, label, files), **options(files, chdir))
          AgentProcess.track(AgentProcess.new(pid:, files:))
        end

        private

        # Its own group, so a terminal's Ctrl-C reaches neither it nor the
        # agent; its own complaints go to the output, where the executor
        # quotes them.
        #
        # @param files [Files]
        # @param chdir [String]
        # @return [Hash]
        def options(files, chdir)
          { chdir:, in: File::NULL, out: File::NULL, err: [files.output, "a"], unsetenv_others: true, pgroup: true }
        end

        # @param label [Label]
        # @return [Files]
        def files_for(label)
          base = File.join(dir, "agent-#{label}-#{::Process.pid}-#{SecureRandom.hex(2)}")
          Files.new(output: "#{base}.out",
            status: "#{base}.status",
            pid_file: File.join(Supervision.dir(root).path, "#{AgentSupervisor::ROLE}-#{label}.pid"))
        end

        # @param argv [Array<String>]
        # @param label [Label]
        # @param files [Files]
        # @return [Array<String>]
        def command(argv, label, files)
          [RbConfig.ruby, "--disable-gems", SCRIPT, "--root", root, "--plan", label.plan, "--agent", label.agent,
           "--output", files.output, "--status", files.status, "--pid-file", files.pid_file, "--", *argv]
        end
      end
    end
  end
end

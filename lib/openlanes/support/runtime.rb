# frozen_string_literal: true

require "digest"
require "fileutils"

module OpenLanes
  # Where a project's runtime files live: outside `.plans/`, under the XDG
  # state directory. A lock or a run record inside `.plans/` sat beside
  # committed documents, so every `git status` and every PR snapshot had to
  # learn to ignore it, and a rename of a locked folder moved the lock with it.
  #
  # Keyed by the project root (the directory that holds `.plans/`), so two
  # checkouts never share a state directory, and the harness and an agent
  # handed the same `--dir` address the same one.
  module Runtime
    module_function

    # @param env [Hash] the environment to read
    # @return [String] absolute `XDG_STATE_HOME`, else `~/.local/state`. An
    #   empty or relative value is ignored, as the XDG spec says.
    def state_home(env = ENV)
      value = env["XDG_STATE_HOME"].to_s
      return value if !value.empty? && value.start_with?("/")

      File.join(Dir.home, ".local", "state")
    end

    # @param root [String] the directory that holds `.plans/`
    # @return [String] `<state_home>/openlanes/<basename>-<6 hex>`, created on demand
    def dir(root:)
      real = begin
        File.realpath(root)
      rescue Errno::ENOENT
        File.expand_path(root)
      end
      path = File.join(state_home, "openlanes", "#{File.basename(real)}-#{Digest::SHA256.hexdigest(real)[0, 6]}")
      FileUtils.mkdir_p(path)
      path
    end

    # @param root [String]
    # @return [String] the directory plan locks are written to
    def locks_dir(root:)
      path = File.join(dir(root:), "locks")
      FileUtils.mkdir_p(path)
      path
    end

    # @param root [String]
    # @return [String] the run's {Engine::StateFile}
    def state_file(root:) = File.join(dir(root:), "openlanes-state.json")
  end
end

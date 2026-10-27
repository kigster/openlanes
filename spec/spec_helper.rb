# frozen_string_literal: true

require "fileutils"
require "simplecov"
require "coverage/badge"

# The badge belongs to the repository, not to the gem whose suite produces it,
# and the suite runs from workflow/. Anchoring on __dir__ rather than on the
# working directory keeps it landing in the one docs/badges the README reads.
#
# The directory is made up front because the move happens in `at_exit`, and
# without it the whole suite dies there — which reports as a passing run
# followed by a stack trace.
#
# The badge is a tracked file, so only a run that asks for it (`just
# test-coverage` sets COVERAGE_BADGE) moves it there. Every other run left
# docs/badges dirty, and verifier, which runs the suite as a How to test
# step, was then refused its commit for "changes outside its plan folder".
REPO_ROOT = File.expand_path("..", __dir__)
BADGE_DIR = File.join(REPO_ROOT, "docs", "badges")
FileUtils.mkdir_p(BADGE_DIR)

SimpleCov.start do
  # `cover` (replacing the deprecated `track_files`) is what makes the number
  # mean anything: without it SimpleCov only counts files some example happened
  # to load, so a library nobody requires reports 100% of nothing. With it, an
  # untested file counts as 0% AND the report is restricted to this pattern —
  # which is also why `spec/` and `bin/` need no separate exclusion below.
  cover "lib/**/*.rb"

  enable_coverage :branch

  self.formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    Coverage::Badge::Formatter
  ]
end

SimpleCov.at_exit do
  SimpleCov.result.format!
  # rubocop: disable RSpec/Output
  puts "Coverage: #{SimpleCov.result.covered_percent.round(2)}%"
  # rubocop: enable RSpec/Output
  FileUtils.mv("coverage/badge.svg", File.join(BADGE_DIR, "coverage_badge.svg")) if ENV["COVERAGE_BADGE"]
end

require "tmpdir"

# Colour is decided by `$stderr.tty?`, which is FALSE under CI (piped) and TRUE
# in a developer's terminal. Left alone, that makes the suite environment-
# dependent: assertions on rendered text see bare strings in CI and ANSI escape
# sequences locally, so a green CI run says nothing about a local one.
#
# Forcing it off makes every content assertion test content. The coloured path
# is still covered — deliberately, by examples that stub `UI.color?` — rather
# than by accident, differently, on each machine.
ENV["NO_COLOR"] = "1"
ENV["GIT_CONFIG_COUNT"] = "1"
ENV["GIT_CONFIG_KEY_0"] = "commit.gpgsign"
ENV["GIT_CONFIG_VALUE_0"] = "false"

# Locks and run records live under the XDG state directory (Runtime). Pointed
# at a per-run temp directory so no example writes into the developer's home.
ENV["XDG_STATE_HOME"] = Dir.mktmpdir("openlanes-state")
at_exit { FileUtils.rm_rf(ENV.fetch("XDG_STATE_HOME")) }

# PID files too (S3): a command run in an example writes its own, and a
# checkout's `tmp/pids` is the developer's running factory.
ENV["OPENLANES_PID_DIR"] = Dir.mktmpdir("openlanes-pids")
at_exit { FileUtils.rm_rf(ENV.fetch("OPENLANES_PID_DIR")) }

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "openlanes"
# dry/system/stubs reopens Dry::System::Container, so the class has to be
# loaded first or the reopening becomes an empty class of its own.
require "dry/system"
require "dry/system/stubs"

require "stringio"

$stderr = StringIO.new

require_relative "support/plans_fixture"
require_relative "support/captured_stream"
require_relative "support/box_text"
require_relative "support/git_repo"
require_relative "support/coverage_fixtures"
require_relative "support/log_helper"
require_relative "support/origin_repo"
require_relative "support/fake_gh_env"
require_relative "support/test_redis"
require_relative "support/port_window"
require_relative "support/ruby_project"

TestRedis.scrub!

# Every key registered up front, so any of them can be stubbed; stubs on, so
# finalizing leaves the container unfrozen. Providers only register lazy
# blocks when they start, so this opens no connection.
OpenLanes::Container.enable_stubs!
OpenLanes::Container.finalize!

RSpec.configure do |config|
  # The choice judge asks TypeSafe over the network. A developer's shell may
  # well export TYPESAFE_API_KEY, so the suite turns the seam off outright;
  # examples about the judge build their own around an adapter double.
  # The choice converter asks OpenRouter, and OPENROUTER_API_KEY sits in
  # this project's own .env, so it is turned off the same way.
  config.before do
    OpenLanes::Live.choice_judge = nil
    OpenLanes::Live.choice_converter = nil
    OpenLanes::Live.interviewer = nil
    # alock is a real command reading a real register (W31); examples about
    # it build their own AgentLocks around a command double.
    OpenLanes::Engine.agent_locks = nil
  end

  # Every real-Redis example holds the machine-wide lock while it runs, and
  # each one flushes its database on entry, so none depends on another run.
  config.around(:example, :redis) { |example| TestRedis.exclusively { example.run } }

  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.mock_with(:rspec) { |m| m.verify_partial_doubles = true }
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed

  config.include PlansFixture
  config.include BoxText
  config.include LogHelper

  # Pastel memoizes `enabled:` at construction, so an example that stubs
  # `tty?` or `color?` would otherwise poison every example that ran after it.
  config.before { OpenLanes::UI.reset! }

  # A stub lasts one example, whether or not it was taken with a block.
  config.after { OpenLanes::Container.unstub }

  # A run sets logging up for its whole process, and the suite is one
  # process: without this, the file one example opened would take every
  # later example's lines. The environment is the engine's hand-off to its
  # server, and a developer's shell exporting it must not steer the suite.
  config.before do
    OpenLanes::Log.reset!
    OpenLanes::Log::Settings.members.each { ENV.delete("OPENLANES_LOG#{"_#{it.upcase}" unless it == :file}") }
  end
  config.after { OpenLanes::Log.reset! }
  # A dispatcher with a state file says its agents outlive it; the suite's own exit still stops them.
  config.after { OpenLanes::Execution::AgentProcess.reset! }

  # A command run in an example names its process (S5); the suite's own
  # title stays `rspec`.
  config.before { allow(Process).to receive(:setproctitle) }

  # Project commands chdir to the root they find. Put the suite back where it
  # was, or one example's root becomes the next example's working directory.
  config.around do |example|
    pwd = Dir.pwd
    example.run
  ensure
    Dir.chdir(pwd)
  end

  # Every example tagged `:tree` gets its own throwaway `.plans` directory, so
  # the suite never reads or writes a real project.
  config.around(:each, :tree) do |example|
    Dir.mktmpdir("openlanes") do |tmp|
      @plans_root = File.join(tmp, OpenLanes::PLANS_DIR)
      FileUtils.mkdir_p(@plans_root)
      example.run
    end
  end
end

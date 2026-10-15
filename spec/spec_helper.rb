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
  FileUtils.mv("coverage/badge.svg", File.join(BADGE_DIR, "coverage_badge.svg"))
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

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "openlanes"

require "stringio"

$stderr = StringIO.new

require_relative "support/plans_fixture"
require_relative "support/captured_stream"
require_relative "support/box_text"
require_relative "support/git_repo"

RSpec.configure do |config|
  # The choice judge asks TypeSafe over the network. A developer's shell may
  # well export TYPESAFE_API_KEY, so the suite turns the seam off outright;
  # examples about the judge build their own around an adapter double.
  config.before { OpenLanes::Live.choice_judge = nil }

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

  # Pastel memoizes `enabled:` at construction, so an example that stubs
  # `tty?` or `color?` would otherwise poison every example that ran after it.
  config.before { OpenLanes::UI.reset! }

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

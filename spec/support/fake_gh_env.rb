# frozen_string_literal: true

require "json"
require "rbconfig"
require "tmpdir"

# The fake `gh` first on PATH for one example, its state and its log in a
# temp directory: for the examples that run the real {OpenLanes::Vcs::GitHub}
# and must still never reach GitHub. Tag an example group `:fake_gh`.
module FakeGhEnv
  # @return [String]
  def fake_gh_home = @fake_gh_home ||= Dir.mktmpdir("openlanes-fake-gh")

  # @return [String] the JSON file the fake answers from
  def gh_state = File.join(fake_gh_home, "state.json")

  # @return [Hash]
  def gh = JSON.parse(File.read(gh_state))

  # @return [Array<Array<String>>] every argv the fake was given, in order
  def gh_calls = File.file?(gh_log) ? File.readlines(gh_log).map { JSON.parse(it) } : []

  # @return [String]
  def gh_log = File.join(fake_gh_home, "argv.log")

  # @yieldparam data [Hash] the state, to change in place
  # @return [void]
  def edit_gh
    data = File.file?(gh_state) ? gh : {}
    yield data
    File.write(gh_state, JSON.generate(data))
  end

  # A pull request as the fake keeps it.
  #
  # @return [Hash]
  def gh_pr(title:, url:, branch: "main", labels: [], checks: [])
    { "title" => title, "url" => url, "branch" => branch, "state" => "OPEN", "merged_at" => nil,
      "labels" => labels, "checks" => checks, "comments" => [] }
  end

  # @return [Hash{String => String}]
  def fake_gh_env
    { "PATH" => "#{File.expand_path("fake_gh", __dir__)}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH")}",
      "FAKE_GH_RUBY" => RbConfig.ruby, "FAKE_GH_STATE" => gh_state, "FAKE_GH_LOG" => gh_log }
  end
end

RSpec.configure do |config|
  config.include FakeGhEnv, :fake_gh
  config.around(:each, :fake_gh) do |example|
    env = fake_gh_env
    saved = ENV.to_h.slice(*env.keys)
    env.each { |key, value| ENV[key] = value }
    example.run
  ensure
    saved.each { |key, value| ENV[key] = value }
    (env.keys - saved.keys).each { ENV.delete(it) }
    FileUtils.rm_rf(fake_gh_home)
  end
end

# frozen_string_literal: true

# Report fixtures for the coverage parsers, under spec/fixtures/coverage.
# Never the repository's own coverage/: every rspec run rewrites that.
module CoverageFixtures
  DIR = File.expand_path("../fixtures/coverage", __dir__)

  # @param name [String]
  # @return [String] absolute path
  def coverage_fixture(name) = File.join(DIR, name)

  # @param name [String]
  # @return [String] the fixture's text
  def coverage_text(name) = File.read(coverage_fixture(name))
end

RSpec.configure { it.include CoverageFixtures }

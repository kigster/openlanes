# frozen_string_literal: true

source "https://rubygems.org"

# What openlanes needs in order to run is declared in the gemspec beside this
# file, so there is one list rather than two that drift. What is left here is
# only what you need in order to work on it.
gemspec

# agent-lock 4.0.0 (the Ruby facade) is not on RubyGems yet. Pinned to its
# main branch by commit until it is; then this line goes and the gemspec
# constraint alone stands.
gem "agent-lock", git: "https://github.com/kigster/agent-lock", ref: "02ef58ccb863f5eb03f71c04cef2f50f6d899de0"

gem "rake"
gem "yard"

group :test do
  gem "coverage-badge"
  gem "rack-test" # drives the API server (OpenLanes::Web) in process
  gem "rspec"
  gem "rspec-its"
  gem "rspec_junit_formatter" # JUnit XML for CircleCI store_test_results
  gem "simplecov"
end

group :development do
  gem "newrelic_rpm"
end

group :development, :test do
  # Already installed at run time through dry-cli-ui -> binding_of_caller; this only pins it for development.
  gem "debug_inspector", "~> 1.2"
  gem "rubocop"
  gem "rubocop-rake"
  gem "rubocop-rspec"
  gem "rubocop-on-rbs"
  gem "rubocop-rubycw"
end

# frozen_string_literal: true

source "https://rubygems.org"

# What openlanes needs in order to run is declared in the gemspec beside this
# file, so there is one list rather than two that drift. What is left here is
# only what you need in order to work on it.
gemspec

gem "rake"
gem "yard"
gem "debug_inspector", "~>1.2"

group :test do
  gem "coverage-badge"
  gem "json_schemer" # validates configuration.example.yml against configuration.schema.json
  gem "rack-test" # drives the API server (OpenLanes::Web) in process
  gem "rspec"
  gem "rspec-its"
  gem "rspec_junit_formatter" # JUnit XML for CircleCI store_test_results
  gem "simplecov"
end

group :development, :test do
  gem "rubocop"
  gem "rubocop-rspec"
  gem "rubocop-rake"
  gem "rubocop-rubycw"
  gem "rubocop-on-rbs"
end

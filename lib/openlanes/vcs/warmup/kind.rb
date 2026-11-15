# frozen_string_literal: true

module OpenLanes
  module Vcs
    class Warmup
      # One kind of dependency, described as data so that adding a kind is
      # adding a row, with no method that has to be named after it.
      #
      # @!attribute [r] name
      #   @return [Symbol]
      # @!attribute [r] inputs
      #   @return [Array<String>] files whose contents decide what is installed;
      #     the last is the lockfile the entry is keyed by
      # @!attribute [r] target
      #   @return [String] where it installs, relative to the worktree
      # @!attribute [r] check
      #   @return [Array<String>, nil] a command that passes when nothing needs
      #     installing
      # @!attribute [r] install
      #   @return [Array<String>]
      # @!attribute [r] env
      #   @return [Proc] `(target) -> Hash` the install's environment
      Kind = Data.define(:name, :inputs, :target, :check, :install, :env) do
        # @return [String]
        def lockfile = inputs.last

        # @return [Boolean] whether it is pointed at its target through `.bundle/config`
        def bundler? = name == :bundler
      end

      # Bundler, installing into a directory under the worktree's `.bundle/`.
      Kind::BUNDLER = Kind.new(
        name:    :bundler,
        inputs:  %w[Gemfile Gemfile.lock],
        target:  ".bundle/openlanes-gems",
        check:   %w[bundle check],
        install: %w[bundle install --quiet],
        env:     ->(target) { { "BUNDLE_PATH" => target } }
      )

      # npm, with no lifecycle scripts, since the branch controls them.
      Kind::NPM = Kind.new(
        name:    :npm,
        inputs:  %w[package.json package-lock.json],
        target:  "node_modules",
        check:   nil,
        install: %w[npm ci --ignore-scripts --silent --no-audit --no-fund],
        env:     ->(_) { {} }
      )
    end
  end
end

# frozen_string_literal: true

require "open3"

module OpenLanes
  module Release
    # Runs `bundle lock` against one checkout's Gemfile.
    #
    # Sets BUNDLE_GEMFILE explicitly: under `bundle exec`, it points at
    # whichever bundle launched us, not at the checkout being bumped. Tries
    # --local first, so a bump needs no network when the gems are installed.
    class Relock
      ATTEMPTS = [%w[bundle lock --local], %w[bundle lock]].freeze

      # @param root [String] the checkout whose Gemfile is relocked
      # @param err [#puts] where a failed attempt's output goes
      def initialize(root, err: $stderr)
        @root = root
        @err = err
      end

      # @return [Boolean] whether an attempt succeeded
      def call
        env = { "BUNDLE_GEMFILE" => File.join(@root, "Gemfile") }
        ATTEMPTS.any? do |argv|
          output, status = Open3.capture2e(env, *argv, chdir: @root)
          @err.puts(output) unless status.success?
          status.success?
        end
      end
    end
  end
end

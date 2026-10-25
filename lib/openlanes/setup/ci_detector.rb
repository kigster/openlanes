# frozen_string_literal: true

module OpenLanes
  module Setup
    # Names the CI a folder already runs (M21), from the files each provider
    # reads. Several at once are reported as a list, never narrowed to one.
    class CiDetector
      # One provider found, and the file or folder that gave it away.
      Found = Data.define(:provider, :path)

      # Provider → glob, relative to the root.
      MARKERS = {
        github_actions: ".github/workflows/*.{yml,yaml}",
        circleci:       ".circleci/config.yml",
        jenkins:        "Jenkinsfile",
        gitlab:         ".gitlab-ci.yml",
        buildkite:      ".buildkite"
      }.freeze

      # @param root [String]
      def initialize(root)
        @root = root
      end

      # @return [Array<OpenLanes::Setup::CiDetector::Found>] empty when none
      def call
        MARKERS.filter_map do |provider, pattern|
          match = Dir.glob(pattern, File::FNM_DOTMATCH, base: @root).min
          Found.new(provider:, path: match) if match
        end
      end
    end
  end
end

# frozen_string_literal: true

require "uri"

module OpenLanes
  module Slack
    # The Slack app a run asks its questions through, as Slack's own "create
    # an app from a manifest" takes it. The file is the one docs/slack.md
    # tells a person to paste, and it ships in the gem.
    module AppManifest
      PATH = File.expand_path("../../../docs/slack-app-manifest.yml", __dir__)

      module_function

      # @return [String] the manifest, its comments left out: they would only
      #   make the link longer
      def yaml = File.readlines(PATH).reject { it.start_with?("#") }.join

      # @return [String] a link that opens Slack's new-app page filled in
      def create_url = "https://api.slack.com/apps?#{URI.encode_www_form(new_app: 1, manifest_yaml: yaml)}"
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Vcs
    # Every open pull request, its labels and its checks, read in one GraphQL
    # query per hundred pull requests.
    #
    # The engine used to ask `gh` per pull request, per step, per tick: a
    # label read here, a `gh pr checks` there, each its own process and its
    # own request against the rate limit. One snapshot is taken per interval
    # and every reader in that tick shares it.
    #
    # @!attribute [r] pulls
    #   @return [Array<Hash>] rows in {GitHub#pull_request}'s shape, each with
    #     `files:` and with `checks:` in {GitHub#checks}'s shape
    # @!attribute [r] taken_at
    #   @return [Time]
    PullSnapshot = Data.define(:pulls, :taken_at) do
      # @param pages [Array<Hash>] decoded GraphQL responses, in order
      # @param taken_at [Time]
      # @return [PullSnapshot]
      def self.parse(pages, taken_at: Time.now)
        nodes = pages.flat_map { it.dig("data", "repository", "pullRequests", "nodes") || [] }
        new(pulls: nodes.map { row(it) }, taken_at:)
      end

      # @param page [Hash] one decoded response
      # @return [String, nil] the cursor of the next page; nil on the last
      def self.next_cursor(page)
        info = page.dig("data", "repository", "pullRequests", "pageInfo") || {}
        info["hasNextPage"] ? info["endCursor"] : nil
      end

      # @param node [Hash] one GraphQL pull request
      # @return [Hash]
      def self.row(node)
        flat = node.merge("labels" => node.dig("labels", "nodes"), "files" => node.dig("files", "nodes"))
        GitHub.row(flat).merge(details(node), checks: checks_of(node))
      end

      # The fields {GitHub#pull_request} reads beyond {GitHub.row}'s, so a
      # snapshot row can stand in for a per-pull-request `gh pr view`.
      #
      # @param node [Hash]
      # @return [Hash]
      def self.details(node)
        {
          head:         node["headRefOid"].to_s,
          body:         node["body"].to_s,
          merge_state:  node["mergeStateStatus"].to_s,
          base:         node["baseRefName"].to_s,
          merge_commit: node.dig("mergeCommit", "oid").to_s
        }
      end

      # @param node [Hash]
      # @return [Array<Hash>] `{name:, bucket:}`
      def self.checks_of(node)
        contexts = node.dig("commits", "nodes", 0, "commit", "statusCheckRollup", "contexts", "nodes") || []
        contexts.map do |c|
          if c["__typename"] == "StatusContext"
            { name: c["context"].to_s, bucket: Buckets.status(c["state"]) }
          else
            { name: c["name"].to_s, bucket: Buckets.check_run(c["status"], c["conclusion"]) }
          end
        end
      end

      # @param number [Integer]
      # @return [Hash, nil] that pull request's row, nil when it is not open
      def [](number) = pulls.find { it[:number] == number.to_i }

      # @param number [Integer]
      # @return [Array<Hash>] its checks, empty when it has none or is not open
      def checks(number) = self[number]&.fetch(:checks) || []

      # @param number [Integer]
      # @return [Array<String>] its label names
      def labels(number) = self[number]&.fetch(:labels) || []

      # @return [Array<Integer>]
      def numbers = pulls.map { it[:number] }
    end

    # One page of open pull requests, with what every reader asks of them.
    PullSnapshot::QUERY = <<~GRAPHQL
      query($owner: String!, $name: String!, $after: String) {
        repository(owner: $owner, name: $name) {
          pullRequests(states: OPEN, first: 100, after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes {
              number title url headRefName headRefOid baseRefName body state isDraft mergedAt mergeStateStatus
              mergeCommit { oid }
              labels(first: 50) { nodes { name } }
              files(first: 100) { nodes { path } }
              commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
                __typename
                ... on CheckRun { name status conclusion }
                ... on StatusContext { context state }
              } } } } } }
            }
          }
        }
      }
    GRAPHQL
  end
end

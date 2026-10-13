# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OpenLanes
  module Linear
    # Linear's GraphQL API, wrapped as thinly as {OpenLanes::Vcs::GitHub} wraps
    # `gh`, and for the same reason: it is a seam. Every example in the suite
    # injects a transport here, so nothing in the tests reaches Linear.
    #
    # Only the dozen operations an import needs are here. This is not a client
    # library, and it should not grow into one — anything Linear can do that
    # `.plans` cannot express does not belong in a tool whose whole premise is
    # that the folder is the source of truth.
    class API
      ENDPOINT = "https://api.linear.app/graphql"

      # The environment variable holding a personal API key.
      TOKEN_VARIABLE = "LINEAR_API_KEY"

      # @return [String, nil] the token, from the environment
      def self.token_from_env = ENV[TOKEN_VARIABLE].to_s.strip.then { |t| t.empty? ? nil : t }

      # @param token [String] a Linear personal API key
      # @param transport [#call, nil] `(query, variables) -> Hash`, for tests
      # @param endpoint [String]
      def initialize(token: nil, transport: nil, endpoint: ENDPOINT)
        @token = token
        @transport = transport
        @endpoint = endpoint
        return if transport || (token && !token.empty?)

        raise Error,
          "no Linear token. Set #{TOKEN_VARIABLE}, or use the MCP transport:\n  " \
          "openlanes linear import <TEAM> -p <PROJECT> --format json"
      end

      # The team, its workflow states and its labels, in one round trip.
      #
      # @param key [String] the team key, e.g. "TAX"
      # @return [Hash] `{id:, name:, key:, states: [...], labels: [...]}`
      # @raise [OpenLanes::Error] when no team wears that key
      def team(key)
        node = query(TEAM, key: key.to_s.upcase).dig("teams", "nodes")&.first
        raise Error, "no Linear team has the key #{key.to_s.upcase}" unless node

        { id: node["id"], name: node["name"], key: node["key"],
         states: node.dig("states", "nodes").to_a, labels: node.dig("labels", "nodes").to_a }
      end

      # @param team_id [String]
      # @return [Array<Hash>] `{id:, name:, url:}`
      def projects(team_id) = query(PROJECTS, teamId: team_id).dig("team", "projects", "nodes").to_a

      # @param input [Hash] `{name:, teamIds:, content:, icon:}`
      # @return [Hash] `{id:, name:, url:}`
      def create_project(input) = unwrap(query(PROJECT_CREATE, input:), "projectCreate", "project")

      # @param id [String]
      # @param input [Hash]
      # @return [Hash]
      def update_project(id, input) = unwrap(query(PROJECT_UPDATE, id:, input:), "projectUpdate", "project")

      # @param input [Hash] `{teamId:, projectId:, title:, description:, stateId:, labelIds:}`
      # @return [Hash] `{id:, identifier:, url:}`
      def create_issue(input) = unwrap(query(ISSUE_CREATE, input:), "issueCreate", "issue")

      # @param id [String] a UUID or an identifier such as "TAX-41"
      # @param input [Hash]
      # @return [Hash]
      def update_issue(id, input) = unwrap(query(ISSUE_UPDATE, id:, input:), "issueUpdate", "issue")

      # @param name [String]
      # @param team_id [String]
      # @return [Hash] `{id:, name:}`
      def create_label(name, team_id)
        unwrap(query(LABEL_CREATE, input: { name:, teamId: team_id }), "issueLabelCreate", "issueLabel")
      end

      # @param issue_id [String]
      # @param url [String]
      # @param title [String]
      # @return [void]
      def link(issue_id:, url:, title:)
        query(ATTACHMENT_CREATE, input: { issueId: issue_id, url:, title: })
      end

      # @param query [String] a GraphQL document
      # @param variables [Hash]
      # @return [Hash] the `data` object
      # @raise [OpenLanes::Error] on a transport or GraphQL error
      def query(query, **variables)
        body = transport.call(query, variables)
        errors = body["errors"]
        raise Error, "Linear rejected the request: #{describe(errors)}" if errors&.any?

        body.fetch("data") { raise Error, "Linear returned no data" }
      end

      private

      # @return [String, nil]
      attr_reader :token

      # @return [String]
      attr_reader :endpoint

      # @return [#call]
      def transport = @transport ||= method(:post)

      # Linear reports a failed mutation as `success: false` rather than as an
      # error, so the envelope has to be checked as well as the errors array.
      #
      # @param data [Hash]
      # @param mutation [String]
      # @param field [String]
      # @return [Hash]
      def unwrap(data, mutation, field)
        payload = data[mutation] or raise Error, "Linear returned no #{mutation} payload"
        raise Error, "Linear declined the #{mutation}" unless payload["success"]

        payload.fetch(field)
      end

      # @param errors [Array<Hash>]
      # @return [String]
      def describe(errors)
        Array(errors).map { |e| e["message"] || e.to_s }.join("; ")
      end

      # @param document [String]
      # @param variables [Hash]
      # @return [Hash] the parsed response body
      def post(document, variables)
        uri = URI(endpoint)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = token
        request.body = JSON.generate(query: document, variables:)

        response = Net::HTTP.start(uri.hostname,
          uri.port,
          use_ssl:      uri.scheme == "https",
          open_timeout: 10,
          read_timeout: 30) { |http| http.request(request) }

        parse(response)
      rescue JSON::ParserError, IOError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
        raise Error, "could not reach Linear at #{endpoint}: #{e.message}"
      end

      # @param response [Net::HTTPResponse]
      # @return [Hash]
      def parse(response)
        return JSON.parse(response.body.to_s) if response.is_a?(Net::HTTPSuccess)

        hint = if ["400", "401"].include?(response.code)
                 "\n\nCheck #{TOKEN_VARIABLE}. A personal API key is sent verbatim, without a `Bearer` prefix."
               end
        raise Error, "Linear returned HTTP #{response.code}#{hint}"
      end

      TEAM = <<~GRAPHQL
        query Team($key: String!) {
          teams(filter: { key: { eq: $key } }, first: 1) {
            nodes {
              id name key
              states(first: 100) { nodes { id name type position } }
              labels(first: 250) { nodes { id name } }
            }
          }
        }
      GRAPHQL

      PROJECTS = <<~GRAPHQL
        query Projects($teamId: String!) {
          team(id: $teamId) {
            projects(first: 250) {
              nodes { id name url description content status { name type } }
            }
          }
        }
      GRAPHQL

      PROJECT_CREATE = <<~GRAPHQL
        mutation CreateProject($input: ProjectCreateInput!) {
          projectCreate(input: $input) { success project { id name url } }
        }
      GRAPHQL

      PROJECT_UPDATE = <<~GRAPHQL
        mutation UpdateProject($id: String!, $input: ProjectUpdateInput!) {
          projectUpdate(id: $id, input: $input) { success project { id name url } }
        }
      GRAPHQL

      ISSUE_CREATE = <<~GRAPHQL
        mutation CreateIssue($input: IssueCreateInput!) {
          issueCreate(input: $input) { success issue { id identifier url } }
        }
      GRAPHQL

      ISSUE_UPDATE = <<~GRAPHQL
        mutation UpdateIssue($id: String!, $input: IssueUpdateInput!) {
          issueUpdate(id: $id, input: $input) { success issue { id identifier url } }
        }
      GRAPHQL

      LABEL_CREATE = <<~GRAPHQL
        mutation CreateLabel($input: IssueLabelCreateInput!) {
          issueLabelCreate(input: $input) { success issueLabel { id name } }
        }
      GRAPHQL

      ATTACHMENT_CREATE = <<~GRAPHQL
        mutation CreateAttachment($input: AttachmentCreateInput!) {
          attachmentCreate(input: $input) { success attachment { id } }
        }
      GRAPHQL
    end
  end
end

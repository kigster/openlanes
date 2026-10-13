# frozen_string_literal: true

module OpenLanes
  module Linear
    # What one {Action} actually did.
    #
    # @!attribute [r] action
    #   @return [OpenLanes::Linear::Action]
    # @!attribute [r] identifier
    #   @return [String, nil] "TAX-41"
    # @!attribute [r] url
    #   @return [String, nil]
    # @!attribute [r] error
    #   @return [String, nil] why it did not happen
    Result = Data.define(:action, :identifier, :url, :error) do
      # @return [Boolean]
      def ok? = error.nil?
    end

    # Applies an {Import} through the {API}, then writes each plan's
    # `linear.md` so the next run knows what this one did.
    #
    # Plans are pushed one at a time and in order. There is no concurrency
    # here on purpose: within a plan the folder's own issue must exist before
    # its children can name it as their parent, and across plans the gain
    # would be a few seconds against the risk of two threads racing to create
    # the same label on a team that does not have it yet.
    class Push
      # @param import [OpenLanes::Linear::Import]
      # @param api [OpenLanes::Linear::API]
      # @param tree [OpenLanes::Plans::Tree]
      def initialize(import:, api:, tree:)
        @import = import
        @api = api
        @tree = tree
      end

      # @return [Array<OpenLanes::Linear::Result>] every action attempted,
      #   skips included, in plan order
      def call
        import.actions.group_by(&:ordinal).flat_map { |ordinal, actions| push_plan(ordinal, actions) }
      end

      private

      # @return [OpenLanes::Linear::Import]
      attr_reader :import

      # @return [OpenLanes::Linear::API]
      attr_reader :api

      # @return [OpenLanes::Plans::Tree]
      attr_reader :tree

      # @return [Hash] the team, its states and its labels
      def team = @team ||= api.team(import.team)

      # @return [String] the project everything is filed under
      def project_id = import.project["id"]

      # @param ordinal [String]
      # @param actions [Array<OpenLanes::Linear::Action>]
      # @return [Array<OpenLanes::Linear::Result>]
      def push_plan(ordinal, actions)
        subject = tree.find(ordinal) or return []
        parents, children = actions.partition { |a| a.unit == Issues::PARENT }
        return [] if parents.empty?

        parent = apply(parents.first, subject, nil)
        results = [parent] + children.map { |action| apply(action, subject, parent) }
        record(subject, results)
        results
      end

      # @param action [OpenLanes::Linear::Action]
      # @param subject [OpenLanes::Plans::Subject]
      # @param parent [OpenLanes::Linear::Result, nil]
      # @return [OpenLanes::Linear::Result]
      def apply(action, subject, parent)
        if parent && !parent.ok?
          return Result.new(action:,
            identifier: action.identifier,
            url: nil,
            error: "the issue for its plan could not be created")
        end

        attempt(action) do
          node = case action.op
                 when :skip then recorded(action, subject)
                 when :update then attach(api.update_issue(action.args[:id], input(action, parent)), action)
                 else attach(api.create_issue(input(action, parent).merge(teamId: team[:id], projectId: project_id)), action)
                 end

          [node["identifier"], node["url"]]
        end
      end

      # A child names its parent by the identifier Linear just handed back,
      # which is why the folder's own issue is pushed first and alone.
      #
      # @param action [OpenLanes::Linear::Action]
      # @param parent [OpenLanes::Linear::Result, nil]
      # @return [Hash]
      def input(action, parent)
        base = { title: action.args[:title], description: action.args[:description],
                stateId: state_id(action.args[:state]), labelIds: label_ids(action.args[:labels]) }.compact
        return base unless parent&.identifier

        base.merge(parentId: parent.identifier)
      end

      # Attaching the pull requests is part of writing the issue, not a
      # decoration on top of it. Linear keys an attachment on its URL, so
      # sending the same one again updates it rather than piling up a second
      # copy — which is what makes this safe on an update.
      #
      # @param node [Hash]
      # @param action [OpenLanes::Linear::Action]
      # @return [Hash]
      def attach(node, action)
        Array(action.args[:links]).each { |l| api.link(issue_id: node["id"], url: l[:url], title: l[:title]) }
        node
      end

      # @param action [OpenLanes::Linear::Action]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Hash]
      def recorded(action, subject)
        was = Issues.new(dir: subject.feature.path).by_unit[action.unit]
        { "identifier" => was&.identifier || action.identifier, "url" => was&.url }
      end

      # A team names its own workflow states, so the name we would prefer is a
      # preference and the type is the contract. Falling back to the type is
      # what lets this run against a workspace whose "In Progress" is called
      # something else entirely.
      #
      # @param name [String]
      # @return [String, nil]
      def state_id(name)
        placement = PLACEMENTS.values.find { |p| p.name == name }
        states = team[:states]

        found = states.find { |s| s["name"].to_s.casecmp?(name.to_s) }
        found ||= states.select { |s| s["type"] == placement&.type }.min_by { |s| s["position"].to_f }
        found && found["id"]
      end

      # @param names [Array<String>]
      # @return [Array<String>]
      def label_ids(names)
        Array(names).map do |name|
          found = team[:labels].find { |l| l["name"].to_s.casecmp?(name) }
          found ||= api.create_label(name, team[:id]).tap { |made| team[:labels] << made }
          found["id"]
        end
      end

      # Every Linear call is wrapped, so one plan that fails — a state the
      # team does not have, a title Linear refuses — does not abandon the
      # twenty plans queued behind it.
      #
      # @param action [OpenLanes::Linear::Action]
      # @yieldreturn [Array(String, String)] identifier and url
      # @return [OpenLanes::Linear::Result]
      def attempt(action)
        identifier, url = yield
        Result.new(action:, identifier:, url:, error: nil)
      rescue Error => e
        Result.new(action:, identifier: action.identifier, url: nil, error: e.message)
      end

      # `linear.md` is rewritten from what actually happened, including the
      # skips — a row dropped because its action was a no-op is a row the next
      # run would recreate from scratch.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param results [Array<OpenLanes::Linear::Result>]
      # @return [void]
      def record(subject, results)
        issues = results.select { |r| r.ok? && r.identifier }.map { |r|
          Issue.new(unit: r.action.unit,
            identifier: r.identifier,
            url: r.url,
            title: r.action.title,
            state: r.action.args[:state] || "",
            digest: r.action.digest)
        }
        return if issues.empty?

        Issues.new(dir: subject.feature.path).write(team: import.team,
          issues:,
          project: { name: import.project_name, url: import.project["url"] })
      end
    end
  end
end

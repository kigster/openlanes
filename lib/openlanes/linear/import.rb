# frozen_string_literal: true

require "json"

module OpenLanes
  module Linear
    # One thing that would happen in Linear.
    #
    # `args` is deliberately shaped as the Linear MCP server's `save_issue`
    # arguments, because that server addresses everything by
    # the names a human already knows — a team by its key, a project by its
    # name, a workflow state by its name, an issue by its identifier. Emitting
    # exactly that shape means the JSON this produces can drive either
    # transport unchanged: {Push} turns it into GraphQL, and the skill hands
    # it to the MCP tools as-is. One contract, so the two cannot drift.
    #
    # @!attribute [r] kind
    #   @return [Symbol] `:issue` for a plan, `:subissue` for a unit of one
    # @!attribute [r] op
    #   @return [Symbol] `:create`, `:update` or `:skip`
    # @!attribute [r] ordinal
    #   @return [String] the plan this belongs to, e.g. "003.00"
    # @!attribute [r] unit
    #   @return [String, nil] the {Unit#key}, nil for a plan's own issue
    # @!attribute [r] identifier
    #   @return [String, nil] what Linear already calls it, when it exists
    # @!attribute [r] title
    #   @return [String] for the human reading the dry run
    # @!attribute [r] digest
    #   @return [String] fingerprint of `args`, recorded after a push
    # @!attribute [r] args
    #   @return [Hash] the MCP argument shape
    # @!attribute [r] reason
    #   @return [String] why this operation and not another
    Action = Data.define(:kind, :op, :ordinal, :unit, :identifier, :title, :digest, :args, :reason) do
      # @return [Boolean] whether this would change anything
      def pending? = op != :skip

      # @return [Boolean] whether this issue hangs off another
      def child? = kind == :subissue

      # @return [Hash] for `--format json`
      def to_h_json
        { kind:, op:, plan: ordinal, unit:, identifier:, title:, digest:, args: }.compact
      end
    end

    # What a plan folder would become in Linear, and what has already become
    # of it. Reads the filesystem; touches nothing else.
    #
    # One folder is one issue, and the units inside its `plan.md` are that
    # issue's children. Projects are never created: a team's project list is
    # something a human curated, and every plan is filed under one the caller
    # named on the command line.
    #
    # Keeping the whole decision offline is what makes `--dry-run` honest. The
    # dry run is not an approximation of what a push would do — it is the same
    # object the push consumes, so what gets printed and what gets sent cannot
    # disagree. Everything that needs the network — the project, the repository
    # pull request list — is handed in.
    class Import
      # @param tree [OpenLanes::Plans::Tree]
      # @param team [String] the team key, e.g. "TAX"
      # @param project [Hash] the Linear project, `{"id", "name", "url"}`
      # @param adopted [Hash{String => Array<OpenLanes::Plans::PullRequest>}]
      #   pull requests {Attribution} placed, by folder name
      # @param since [String, nil] skip plans numbered below this
      # @param statuses [Array<Symbol>, nil] only these states
      # @param update_unchanged [Boolean] update everything, matching digest or not
      def initialize(tree:, team:, project:, adopted: {}, since: nil, statuses: nil, update_unchanged: false)
        @tree = tree
        @team = team.to_s.strip.upcase
        @project = project
        @adopted = adopted
        @since = since && Plans::Ordinal.parse(since)
        @statuses = statuses
        @update_unchanged = update_unchanged
      end

      # @return [String] the team key
      attr_reader :team

      # @return [Hash] the project everything is filed under
      attr_reader :project

      # @return [String]
      def project_name = project["name"].to_s

      # @return [Array<OpenLanes::Linear::Action>] each plan's issue,
      #   followed by that issue's children
      def actions = @actions ||= subjects.flat_map { |s| actions_for(s) }

      # @return [Array<OpenLanes::Linear::Action>]
      def pending = actions.select(&:pending?)

      # @return [String] the whole import, for a pipe
      def to_json(*_args)
        JSON.pretty_generate(team:, project: project_name, actions: actions.map(&:to_h_json))
      end

      # Plans in a state nobody has decided how to file, and why not.
      #
      # @return [Hash{OpenLanes::Plans::Status => Array<String>}] state => ordinals
      def unplaced
        @unplaced ||= (chosen - subjects).group_by(&:status)
                                         .transform_values { |group| group.map { |s| s.feature.ordinal.to_s } }
      end

      private

      # @return [OpenLanes::Plans::Tree]
      attr_reader :tree

      # @return [Hash]
      attr_reader :adopted

      # @return [OpenLanes::Plans::Ordinal, nil]
      attr_reader :since

      # @return [Array<Symbol>, nil]
      attr_reader :statuses

      # @return [Boolean]
      attr_reader :update_unchanged

      # @return [Array<OpenLanes::Plans::Subject>]
      def subjects = @subjects ||= chosen.select { |s| OpenLanes::Linear.placement(s.status) }

      # @return [Array<OpenLanes::Plans::Subject>] before the placement question
      def chosen
        @chosen ||= tree.subjects.select { |s|
          (since.nil? || s.feature.ordinal >= since) &&
            (statuses.nil? || statuses.include?(s.status.key))
        }
      end

      # The units a plan's issue will have children for: the ones its
      # `plan.md` declares, plus any pull request {Attribution} placed here
      # that none of them already claims.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<OpenLanes::Linear::Unit>]
      def units_for(subject)
        (@units ||= {})[subject.feature.path] ||= begin
          declared = Units.new(subject:).all
          claimed = declared.flat_map(&:pull_requests).map(&:number)
          extra = adopted.fetch(subject.feature.dirname, []).reject { |pr| claimed.include?(pr.number) }
          declared + extra.map { |pr| adopted_unit(pr) }
        end
      end

      # @param pull [OpenLanes::Plans::PullRequest]
      # @return [OpenLanes::Linear::Unit]
      def adopted_unit(pull)
        Unit.new(key: "##{pull.number}",
          title: Units.clean_title(pull.title),
          body: "",
          pull_requests: [pull])
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [OpenLanes::Linear::Issues]
      def record_for(subject) = (@records ||= {})[subject.feature.path] ||= Issues.new(dir: subject.feature.path)

      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<OpenLanes::Linear::Action>]
      def actions_for(subject)
        [plan_action(subject)] + units_for(subject).map { |unit| unit_action(subject, unit) }
      end

      # The issue that stands for the whole plan folder.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [OpenLanes::Linear::Action]
      def plan_action(subject)
        placement = OpenLanes::Linear.placement(subject.status)
        recorded = record_for(subject).by_unit[Issues::PARENT]
        title = plan_title(subject)

        args = { team:, project: project_name, title:, description: plan_description(subject),
                state: placement.name, labels: placement.labels }
        digest = Issues.digest(args)

        op, reason = decide(recorded&.identifier, recorded&.digest, digest)
        args = args.merge(id: recorded.identifier).except(:team, :project) if op == :update && recorded

        Action.new(kind: :issue,
          op:,
          ordinal: subject.feature.ordinal.to_s,
          unit: Issues::PARENT,
          identifier: recorded&.identifier,
          title:,
          digest:,
          args:,
          reason:)
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @param unit [OpenLanes::Linear::Unit]
      # @return [OpenLanes::Linear::Action]
      def unit_action(subject, unit)
        placement = OpenLanes::Linear.placement_for(subject.status, unit.pull_requests)
        recorded = record_for(subject).by_unit[unit.key]
        parent = record_for(subject).by_unit[Issues::PARENT]

        args = { team:, project: project_name, title: unit.title,
                description: unit_description(subject, unit),
                state: placement.name, labels: placement.labels, links: links_for(unit) }
        args = args.merge(parentId: parent.identifier) if parent
        digest = Issues.digest(args.except(:parentId))

        op, reason = decide(recorded&.identifier, recorded&.digest, digest)
        args = args.merge(id: recorded.identifier).except(:team, :project) if op == :update && recorded

        Action.new(kind: :subissue,
          op:,
          ordinal: subject.feature.ordinal.to_s,
          unit: unit.key,
          identifier: recorded&.identifier,
          title: unit.title,
          digest:,
          args:,
          reason:)
      end

      # The three-way decision, in one place so a plan and a unit cannot
      # answer it differently.
      #
      # @param existing [String, nil] what Linear already calls it
      # @param was [String, nil] the digest recorded at the last push
      # @param now [String] the digest of what we would push
      # @return [Array(Symbol, String)] the operation and its reason
      def decide(existing, was, now)
        return [:create, "not recorded in #{Issues::FILENAME}"] if existing.nil?
        return [:update, "--update-unchanged"] if update_unchanged
        return [:skip, "unchanged since the last import"] if was == now

        [:update, "the plan has changed since #{existing} was pushed"]
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def plan_title(subject) = "[#{subject.feature.ordinal}] #{heading(subject)}"

      # The specification's own H1 when it has one, because an agent writing
      # `spec.md` gives it a real sentence — "Tenancy: users, households,
      # memberships" — while the folder slug can only carry kebab-case.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def heading(subject)
        line = subject.read("spec.md").to_s[/^[ \t]{0,3}#[ \t]+(.+)$/, 1]
        cleaned = line.to_s.sub(/\A(?:spec(?:ification)?\s*)?\d+(?:\.\d+)?\s*[—–:.-]\s*/i, "").strip
        cleaned.empty? ? subject.feature.title : cleaned
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @return [String]
      def plan_description(subject)
        [
          subject.goal.join("\n\n"),
          "**State**: #{subject.status} — #{subject.status.note}",
          "**Folder**: `#{OpenLanes::PLANS_DIR}/#{subject.feature.dirname}`",
          provenance
        ].compact.reject(&:empty?).join("\n\n")
      end

      # @param subject [OpenLanes::Plans::Subject]
      # @param unit [OpenLanes::Linear::Unit]
      # @return [String]
      def unit_description(subject, unit)
        [
          truncate(unit.body),
          "**Plan**: `#{OpenLanes::PLANS_DIR}/#{subject.feature.dirname}` · unit `#{unit.key}`",
          provenance
        ].compact.reject(&:empty?).join("\n\n")
      end

      # A pull request is attached to its issue, not listed in its body.
      #
      # Linear has a first-class relationship for this and renders it as what
      # it is — an artifact implementing the work, carrying its own state. A
      # markdown bullet is a claim about a relationship; an attachment is the
      # relationship. Links are keyed on the URL, so re-sending one updates
      # rather than duplicates.
      #
      # @param unit [OpenLanes::Linear::Unit]
      # @return [Array<Hash>]
      def links_for(unit)
        unit.pull_requests.select(&:url).map { |pr| { url: pr.url, title: pr.label } }
      end

      # A plan section can run to several hundred lines of design notes and
      # DDL. Linear is where the work is tracked, not where it is specified,
      # and the folder is one click away.
      #
      # @param body [String]
      # @param limit [Integer]
      # @return [String]
      def truncate(body, limit = 6_000)
        text = body.to_s.strip
        return text if text.length <= limit

        "#{text[0, limit].rpartition("\n").first.rstrip}\n\n_…truncated; the plan folder has the rest._"
      end

      # @return [String]
      def provenance
        "_Imported by `openlanes linear import`. The plan folder is the source of truth; " \
          "edits made here do not travel back._"
      end
    end
  end
end

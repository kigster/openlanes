# frozen_string_literal: true

module OpenLanes
  module Agents
    # Loads and indexes the agent definitions.
    class Registry
      # Where definitions live, unless told otherwise.
      DEFAULT_DIR = File.expand_path("../../../agents", __dir__)

      # @param dir [String]
      # @param roster [Array<OpenLanes::Agents::Agent>, nil] a pre-selected list, used
      #   by {#only} and {#without} to derive a narrower roster; nil (the
      #   default) loads every definition in `dir`
      def initialize(dir: DEFAULT_DIR, roster: nil)
        @dir = File.expand_path(dir)
        @all = roster
      end

      # @return [String]
      attr_reader :dir

      # @return [Array<OpenLanes::Agents::Agent>] in name order
      def all
        @all ||= Dir.glob(File.join(dir, "*.md")).sort.filter_map { |path| parse(path) }
      end

      # @param name [String]
      # @return [OpenLanes::Agents::Agent, nil]
      def find(name) = all.find { |a| a.name == name.to_s }

      # A roster holding only the agents named — what `run --agent` hands the
      # loop, so a restriction typed at the command line restricts assignments
      # and not merely chaining.
      #
      # @param names [Array<String>]
      # @return [OpenLanes::Agents::Registry]
      def only(*names)
        wanted = names.flatten.map(&:to_s)
        self.class.new(dir:, roster: all.select { |a| wanted.include?(a.name) })
      end

      # A roster without the agents named — what `run --skip` hands the loop.
      # A plan sitting in a skipped agent's state is simply never assigned, the
      # same way a state no agent handles is stepped around.
      #
      # @param names [Array<String>]
      # @return [OpenLanes::Agents::Registry]
      def without(*names)
        unwanted = names.flatten.map(&:to_s)
        self.class.new(dir:, roster: all.reject { |a| unwanted.include?(a.name) })
      end

      # Every agent the query could mean. An exact name wins outright; failing
      # that the query matches as a prefix, and failing that anywhere in the
      # name, so `leah` finds leah-researcher and `review` finds
      # hansolo-reviewer. A directory or a trailing `.md` is stripped first,
      # because tab completion hands those in.
      #
      # @param query [String]
      # @return [Array<OpenLanes::Agents::Agent>]
      def match(query)
        wanted = File.basename(query.to_s, ".md")
        exact = all.select { |a| a.name == wanted }
        return exact unless exact.empty?

        prefixed = all.select { |a| a.name.start_with?(wanted) }
        return prefixed unless prefixed.empty?

        all.select { |a| a.name.include?(wanted) }
      end

      # Every agent that will act on a plan in this state, in definition order.
      # A read-only agent is never offered work by the loop — it has nothing to
      # advance, so including it would make every round look productive.
      #
      # @param status [OpenLanes::Plans::Status]
      # @return [Array<OpenLanes::Agents::Agent>]
      def for_status(status) = all.select { |a| a.handles?(status) && !a.read_only? }

      # Everyone on a plan in this state: the agents that work it, plus any
      # agent whose `holds_at` parks the plan here after it finished its half.
      # Rey resuming a plan at 🎨 still needs luke's messages in the mailbox.
      #
      # @param status [OpenLanes::Plans::Status]
      # @return [Array<OpenLanes::Agents::Agent>]
      def team_for(status) = all.select { |a| !a.read_only? && (a.handles?(status) || a.holds_at == status.key) }

      private

      # @param path [String]
      # @return [OpenLanes::Agents::Agent, nil]
      def parse(path)
        meta, body = Frontmatter.split(File.read(path, encoding: "UTF-8"))
        return nil if meta["name"].to_s.empty?

        Agent.new(
          name:          meta["name"].to_s,
          description:   meta["description"].to_s,
          handles:       Array(meta["handles"]).map { |s| s.to_s.to_sym },
          advances_to:   meta["advances_to"]&.to_s&.then { |s| s.empty? ? nil : s.to_sym },
          model:         meta["model"],
          allowed_tools: Array(meta["allowed_tools"]).map(&:to_s),
          may:           Array(meta["may"]).map { |c| c.to_s.strip.squeeze(" ") },
          network:       meta["network"] == true,
          timeout:       meta["timeout"].to_i.then { |s| s.positive? ? s : nil },
          prompt:        body.strip,
          path:          path,
          ledger:        Array(meta["ledger"]).map(&:to_s),
          rounds:        meta["rounds"].to_i.clamp(1, Agent::MAX_ROUNDS),
          effort:        effort(meta["effort"], path),
          starts_as:     symbol_or_nil(meta["starts_as"]),
          holds_at:      symbol_or_nil(meta["holds_at"]),
          adapter:       adapter(meta["adapter"], path),
          phase:         meta["phase"]&.to_s,
          lanes:         Array(meta["lanes"]).map { |l| l.to_s.to_sym },
          needs:         Array(meta["needs"]).map(&:to_s),
          toggle:        meta["toggle"]&.to_s
        )
      end

      # A definition is checked in with the code, so a bad value in one is a
      # bug to stop on, not a preference to work around.
      #
      # @param value [Object, nil]
      # @param path [String]
      # @return [String, nil]
      # @raise [OpenLanes::Error]
      def effort(value, path)
        return nil if value.nil?
        return value.to_s if Adapters.effort?(value)

        raise OpenLanes::Error, "#{File.basename(path)}: effort #{value.inspect} is not one of #{Adapters::EFFORTS.join(", ")}"
      end

      # @param value [Object, nil]
      # @param path [String]
      # @return [String]
      # @raise [OpenLanes::Error]
      def adapter(value, path)
        return Adapters::DEFAULT if value.nil?
        return value.to_s if Adapters.known?(value)

        raise OpenLanes::Error, "#{File.basename(path)}: adapter #{value.inspect} is not one of #{Adapters.names.join(", ")}"
      end

      # @param value [Object, nil]
      # @return [Symbol, nil]
      def symbol_or_nil(value) = value.to_s.empty? ? nil : value.to_s.to_sym
    end
  end
end

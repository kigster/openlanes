# frozen_string_literal: true

module OpenLanes
  module Agents
    # Whether an agent that handles a plan's state should actually be given
    # the plan. Handling the state is necessary, not sufficient: the plan's
    # lane may route around the agent, its spec.md may switch it off, or the
    # files it builds from may hold nothing for it to do.
    #
    # The front end is the case that motivated this. rey-frontend used to be
    # started on every planned folder, and spent ten minutes and five dollars
    # on a plan whose interface was three lines of terminal output.
    module Routing
      # A work unit in a plan file: a second- or third-level heading. A title
      # line does not count, so a `plan-frontend.md` that is only a heading
      # and "no front-end units" starts nobody.
      UNIT_HEADING = /^[ \t]{0,3}\#{2,3}[ \t]+\S/

      module_function

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @param spec [OpenLanes::Plans::Spec]
      # @return [Boolean]
      def allows?(agent, subject, spec = Plans::Spec.for(subject))
        return false unless agent.serves?(spec.lane)
        return false unless reviewable?(agent, subject)

        switch = toggled(agent, spec)
        return switch unless switch.nil?

        agent.needs.all? { |file| units?(subject, file) }
      end

      # The agents in +agents+ this plan should get, in their given order.
      #
      # {Agent#needs} only ever chooses between agents. When lanes and
      # switches leave one candidate, that one runs: a plan parked at 🎨 is
      # rey-frontend's to finish whatever `plan-frontend.md` says, and an
      # operator who typed `--agent rey-frontend` meant it.
      #
      # @param agents [Array<OpenLanes::Agents::Agent>]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<OpenLanes::Agents::Agent>]
      def filter(agents, subject)
        spec = Plans::Spec.for(subject)
        routed = agents.select do |agent|
          agent.serves?(spec.lane) && toggled(agent, spec) != false && reviewable?(agent, subject)
        end
        return routed if routed.size <= 1

        routed.select { |agent| toggled(agent, spec) || agent.needs.all? { |file| units?(subject, file) } }
      end

      # What the spec's switch for this agent says: true forces it, false
      # forbids it, nil leaves the decision to {Agent#needs}. A spec.md that
      # says nothing takes the project's answer from `.openlanes.yml`, so a
      # command-line tool can say once that no plan of it has a front end.
      #
      # @param config [OpenLanes::Config] the project's settings
      # @return [Boolean, nil]
      def toggled(agent, spec, config = OpenLanes::Config.current)
        return nil if agent.toggle.nil?
        return nil unless spec.respond_to?(agent.toggle)

        value = spec.public_send(agent.toggle)
        return value unless value.nil?

        config.public_send(agent.toggle) if config.respond_to?(agent.toggle)
      end

      # A reviewer reviews a pull request, through `gh pr diff`. A plan that
      # reached 🟢 with none open (a shared-tree run, or --no-git-push) would
      # hand it nothing to read, so the plan waits at 🟢 until one exists;
      # `resync prs` records one a human opened.
      #
      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Boolean]
      def reviewable?(agent, subject) = agent.phase.to_s != "review" || subject.pull_requests.any?(&:open?)

      # @param subject [OpenLanes::Plans::Subject]
      # @param file [String]
      # @return [Boolean]
      def units?(subject, file) = Plans::Ledger.stripped(subject.read(file)).match?(UNIT_HEADING)
    end
  end
end

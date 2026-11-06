# frozen_string_literal: true

module OpenLanes
  module Agents
    # Whether an agent that handles a plan's state should actually be given
    # the plan. Handling the state is necessary, not sufficient: the plan's
    # lane may route around the agent, its spec.md may switch it off, or the
    # files it builds from may hold nothing for it to do.
    #
    # The front end is the case that motivated this. frontend-coder used to be
    # started on every planned folder, and spent ten minutes and five dollars
    # on a plan whose interface was three lines of terminal output.
    module Routing
      # A work unit in a plan file: a second- or third-level heading. A title
      # line does not count, so a `plan-frontend.md` that is only a heading
      # and "no front-end units" starts nobody.
      UNIT_HEADING = /^[ \t]{0,3}\#{2,3}[ \t]+\S/

      # A work unit inside a section of `plan.md`: the section is the `##`,
      # so only a deeper heading is a unit.
      SECTION_UNIT_HEADING = /^[ \t]{0,3}\#{3,4}[ \t]+\S/

      # Any second-level heading, which ends the section before it.
      SECTION_HEADING = /^[ \t]{0,3}\#\#[ \t]+(.+?)[ \t#]*$/

      module_function

      # @param agent [OpenLanes::Agents::Agent]
      # @param subject [OpenLanes::Plans::Subject]
      # @param spec [OpenLanes::Plans::Spec]
      # @return [Boolean]
      def allows?(agent, subject, spec = Plans::Spec.for(subject))
        return false unless agent.serves?(spec.starts)
        return false unless reviewable?(agent, subject)

        switch = toggled(agent, spec)
        return switch unless switch.nil?

        agent.needs.all? { |file| units?(subject, file) }
      end

      # The agents in +agents+ this plan should get, in their given order.
      #
      # {Agent#needs} only ever chooses between agents. When lanes and
      # switches leave one candidate, that one runs: a plan parked at 🎨 is
      # frontend-coder's to finish whatever `plan.md`'s `## Frontend` says, and an
      # operator who typed `--agent frontend-coder` meant it.
      #
      # @param agents [Array<OpenLanes::Agents::Agent>]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<OpenLanes::Agents::Agent>]
      def filter(agents, subject)
        spec = Plans::Spec.for(subject)
        routed = agents.select do |agent|
          agent.serves?(spec.starts) && toggled(agent, spec) != false && reviewable?(agent, subject)
        end
        return routed if routed.size <= 1

        routed.select { |agent| toggled(agent, spec) || agent.needs.all? { |file| units?(subject, file) } }
      end

      # The agents a plan in +status+ is offered: those that handle the state,
      # routed by {.filter}; when routing leaves none of them, those that
      # cover it, routed the same way.
      #
      # 🎨 is why (issue 174). frontend-coder alone handles it, so a plan that
      # reached it and then had its front end switched off, or its lane moved
      # to building, was offered to nobody and sat at 🎨 for ever. Its back-end
      # builder covers 🎨 instead: offered only then, never beside a
      # frontend-coder that routes, and its Completed submits the plan to 🟢
      # through the same publish every build takes. A harness hop like
      # {Lifecycle::Lanes} could not do it: 🟢 needs a pull request, and only
      # a completed build opens one.
      #
      # Whether a handler would route is asked of the whole roster, so a
      # handler the run skipped holds the state rather than ceding it.
      #
      # @param registry [OpenLanes::Agents::Registry]
      # @param status [OpenLanes::Plans::Status]
      # @param subject [OpenLanes::Plans::Subject]
      # @return [Array<OpenLanes::Agents::Agent>]
      def offer(registry, status, subject)
        routed = filter(registry.for_status(status), subject)
        return routed unless routed.empty? && filter(registry.whole.for_status(status), subject).empty?

        filter(registry.covering(status), subject)
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

      # Whether +need+ holds a work unit. A need is a file (`plan-frontend.md`)
      # or a section of one (`plan.md#frontend`: the `## Frontend` section,
      # matched without regard to case). Units moved into `plan.md` in plan
      # 003; a folder planned before that still holds `plan-<section>.md`, and
      # is read from there when `plan.md` has no such section, so no folder
      # needs migrating.
      #
      # @param subject [OpenLanes::Plans::Subject]
      # @param need [String]
      # @return [Boolean]
      def units?(subject, need)
        file, section = need.split("#", 2)
        return Plans::Ledger.stripped(subject.read(file)).match?(UNIT_HEADING) unless section

        body = section_of(Plans::Ledger.stripped(subject.read(file)), section)
        return body.match?(SECTION_UNIT_HEADING) if body

        units?(subject, "plan-#{section.downcase}.md")
      end

      # @param text [String]
      # @param name [String]
      # @return [String, nil] the lines under `## name`, up to the next `##`;
      #   nil when there is no such heading
      def section_of(text, name)
        body = nil
        text.each_line do |line|
          if (heading = SECTION_HEADING.match(line))
            break if body

            body = +"" if heading[1].strip.casecmp?(name)
          elsif body
            body << line
          end
        end
        body
      end
    end
  end
end

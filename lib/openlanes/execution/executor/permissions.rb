# frozen_string_literal: true

module OpenLanes
  module Execution
    class Executor
      # What {Executor} answers about the tools and commands an agent may use.
      module Permissions
        # @see Grants.denied_for
        def denied_for(agent) = Grants.denied_for(agent)

        # @see Confinement.allowed_for
        def allowed_for(agent, subject) = Confinement.allowed_for(agent, subject)

        # @see Grants.denied_commands
        def denied_commands(agent) = Grants.denied_commands(agent)

        # @see Grants.granted_to
        def granted_to(agent) = Grants.granted_to(agent)
      end
    end
  end
end

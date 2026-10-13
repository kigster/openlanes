# frozen_string_literal: true

module OpenLanes
  # The specialists: their definitions in `agents/*.md`, the registry that
  # loads and filters them, and the roster that reports on them.
  module Agents
    module_function

    # @param dir [String] where the definitions live
    # @return [OpenLanes::Agents::Registry]
    def registry(dir: Registry::DEFAULT_DIR) = Registry.new(dir:)

    # @param name [String]
    # @return [OpenLanes::Agents::Agent, nil]
    def find(name, dir: Registry::DEFAULT_DIR) = registry(dir:).find(name)

    # @return [OpenLanes::Agents::Roster]
    def roster(**) = Roster.new(**)
  end
end

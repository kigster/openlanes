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

    # The phases the definitions name, the vocabulary a lesson's
    # `applies_to:` and `checked_by:` address besides agent names.
    #
    # @param dir [String] where the definitions live
    # @return [Array<String>] sorted, each once
    def phases(dir: Registry::DEFAULT_DIR) = registry(dir:).all.filter_map(&:phase).uniq.sort

    # @return [OpenLanes::Agents::Roster]
    def roster(**) = Roster.new(**)
  end
end

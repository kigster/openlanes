# frozen_string_literal: true

module OpenLanes
  module Uml
    # A constant as written, with the lexical scopes it was written in,
    # innermost first. Resolving it needs every definition in the project,
    # which one file cannot know, so the parser records and {Index} resolves.
    #
    # @!attribute path [String] "Plans::Status", never with a leading `::`
    # @!attribute scope [Array<String>] the enclosing names, innermost first;
    #   empty for `::Foo`, which Ruby looks up at the top level only
    Reference = Data.define(:path, :scope)
  end
end

# frozen_string_literal: true

module OpenLanes
  module Uml
    # A directed, typed edge between two drawn classes.
    #
    # @!attribute from [String]
    # @!attribute to [String]
    # @!attribute kind [Symbol] :inherits, :includes or :uses
    Edge = Data.define(:from, :to, :kind)
  end
end

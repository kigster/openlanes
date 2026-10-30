# frozen_string_literal: true

module OpenLanes
  module Setup
    # Where a description may go to be read: the person's own credentials,
    # never ours (decision A21).
    module Extraction
      # One place a description can be sent.
      #
      # @!attribute [r] label
      #   @return [String] named to the person before they type anything
      # @!attribute [r] adapter
      #   @return [#call] builds the Inquirex adapter, on first use
      Route = Data.define(:label, :adapter)

      module_function

      # @param env [#[]]
      # @return [OpenLanes::Setup::Extraction::Route, nil] nil when nothing can read it
      def route(env = ENV) = Routes.new(env:).first
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Memory
    # One file a source handed over: its text, and how an agent reads it back.
    #
    # @!attribute [r] path
    #   @return [String] where it came from, for problem reports
    # @!attribute [r] text
    #   @return [String] the whole file, not yet checked for encoding
    # @!attribute [r] cite
    #   @return [String] what the prompt tells an agent to read, e.g.
    #     `git show 1a2b3c4:.openlanes/memory/lessons/L-1.md`
    Entry = Data.define(:path, :text, :cite)
  end
end

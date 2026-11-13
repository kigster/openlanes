# frozen_string_literal: true

module OpenLanes
  module Memory
    # A lesson waiting in the inbox: what was proposed, and the plans it was
    # seen in.
    #
    # @!attribute [r] slug
    #   @return [String] its file name without `.md`, and its `id:` while it waits
    # @!attribute [r] meta
    #   @return [Hash{String => Object}] its frontmatter as written
    # @!attribute [r] body
    #   @return [String]
    # @!attribute [r] path
    #   @return [String]
    Candidate = Data.define(:slug, :meta, :body, :path) do
      # @return [Array<Hash{String => String}>] each `{ "plan", "finding" }`
      def sources = Array(meta["source"]).grep(Hash)

      # @return [Array<String>] the distinct plans it was seen in
      def plans = sources.map { it["plan"].to_s }.reject(&:empty?).uniq

      # @return [Boolean] whether a person said to promote it whatever the count
      def approved? = meta["approved"] == true

      # @return [String]
      def title = meta["title"].to_s
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Setup
    # A project's stack: the fields `stack:` holds in `.openlanes.yml`
    # ({Config::STACK_FIELDS}), each nil until somebody answered it.
    # `frameworks` is a list; every other field is one name.
    Stack = Data.define(*Config::STACK_FIELDS) do
      def initialize(**fields)
        super(**Config::STACK_FIELDS.to_h { [it, nil] }, **fields)
      end

      # Builds one from the config's shape, string or symbol keys.
      #
      # @param hash [Hash, nil]
      # @return [OpenLanes::Setup::Stack]
      def self.from_h(hash)
        fields = (hash || {}).transform_keys(&:to_sym).slice(*Config::STACK_FIELDS)
        new(**fields)
      end

      # The `.openlanes.yml` shape: answered fields only, so an unknown is
      # left out rather than written as a placeholder.
      #
      # @return [Hash{Symbol => Object}]
      def to_h = super.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }

      # @return [Boolean] whether nothing was answered
      def empty? = to_h.empty?
    end
  end
end

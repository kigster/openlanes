# frozen_string_literal: true

# The checkout's own `.openlanes.yml` is the developer's factory setting, not a
# fixture. When it said `frontend: true` and `desired_codebase_quality: high`,
# routing and run specs that never wrote a config of their own read it through
# {OpenLanes::Config.current} and failed on a clean checkout (plan 056, B1).
#
# Loading the checkout's root therefore yields an empty config. Every other
# root passes through, so an example that writes its own `.openlanes.yml` into
# a temp directory still reads it. An example about the checkout's real file
# opts back in with the `:checkout_config` tag.
module CheckoutConfig
  ROOT = File.expand_path("../..", __dir__)

  class << self
    attr_accessor :real

    # @param root [String]
    # @return [Boolean] true when the root is this checkout and the example has not opted in
    def pinned?(root) = !real && File.expand_path(root) == ROOT
  end

  # Prepended to Config's singleton, so both `load` and `current` (which loads)
  # see it.
  module Pin
    # @param root [String]
    # @return [OpenLanes::Config]
    def load(root)
      CheckoutConfig.pinned?(root) ? new : super
    end
  end
end

OpenLanes::Config.singleton_class.prepend(CheckoutConfig::Pin)

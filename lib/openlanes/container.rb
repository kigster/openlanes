# frozen_string_literal: true

require "dry/system"

module OpenLanes
  # The application's components, and the outside world they reach (A1).
  #
  # Two kinds of key:
  #
  # - **A dotted key is a class under `lib/openlanes/`**, keyed by its path:
  #   `engine/upkeep/owed.rb` is `engine.upkeep.owed`. Collapsed directories
  #   keep their place in the key (`support/clock.rb` is `support.clock`,
  #   though the constant is `OpenLanes::Clock`), because the constant is
  #   asked of {LOADER} rather than inflected from the key a second time.
  # - **A bare key is a provider** from `lib/openlanes/providers/<key>.rb`:
  #   `github`, `linear`, `redis`, `event_bus`, `logger`, `clock`, `process`.
  #   Each hands out what the code builds by hand today, configured the same
  #   way.
  #
  # Nothing is loaded ahead of use: a key is found, and its file loaded, the
  # first time it is resolved. The suite finalizes the container with stubs
  # enabled, so a spec swaps a component for the length of one example:
  #
  # @example
  #   OpenLanes::Container["github"]                        # a Vcs::GitHub
  #   OpenLanes::Container.stub("github", fake) { ... }     # in a spec
  #   include OpenLanes::Deps["github", "clock"]            # in a class
  class Container < Dry::System::Container
    # Builds a component from the constant Zeitwerk expects at its file.
    #
    # The default loader camelizes the key, which would need the collapsed
    # directories and the acronyms (`GitHub`, `CLI`) written down twice, and
    # two copies of an inflection table drift.
    #
    # A module is handed out as itself: a facade (`vcs`, `engine.upkeep`) is
    # a set of module methods, and `Module#new` does not exist to call.
    class Loader < Dry::System::Loader::Autoloading
      # @param component [Dry::System::Component]
      # @return [Object] an instance of the class, or the module itself
      def self.call(component, *, **)
        constant = constant(component)
        constant.is_a?(Class) ? super : constant
      end

      # @param component [Dry::System::Component]
      # @return [Module]
      def self.constant(component) = Object.const_get(LOADER.cpath_expected_at(component.file_path))
    end

    # Files that are this wiring rather than the application.
    WIRING = %w[OpenLanes::Container OpenLanes::Deps].freeze

    # Only files Zeitwerk names a constant for are components: an ignored
    # file (a provider, a template, a file loaded by hand) has none to build.
    REGISTERABLE = lambda do |component|
      cpath = LOADER.cpath_expected_at(component.file_path)
      !cpath.nil? && !WIRING.include?(cpath)
    end

    configure do |config|
      config.name = :openlanes
      config.root = File.expand_path("../..", __dir__)
      config.provider_dirs = ["lib/openlanes/providers"]
      config.component_dirs.add("lib/openlanes") do |dir|
        dir.loader = Loader
        dir.add_to_load_path = false
        dir.auto_register = REGISTERABLE
      end
    end
  end
end

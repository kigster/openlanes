# frozen_string_literal: true

module OpenLanes
  # Constructor injection from {Container}: `include Deps["github"]` gives a
  # class a `github:` keyword that defaults to the container's, so a caller
  # may still pass its own and a spec may stub the key instead.
  Deps = Container.injector
end

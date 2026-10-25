# frozen_string_literal: true

# GitHub through `gh`, the seam everything that leaves the machine goes
# through. Not memoized: {OpenLanes::Vcs.github} hands out a new one per call,
# and a client rooted elsewhere (`chdir:`) is still built by hand.
OpenLanes::Container.register_provider(:github) do
  start { register("github") { OpenLanes::Vcs::GitHub.new } }
end

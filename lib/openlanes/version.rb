# frozen_string_literal: true

# Alone in its own file, requiring nothing, so the gemspec can read the version
# without loading the library — and therefore without the library's own
# dependencies having to be installed before the gemspec can be evaluated.
#
# © 2026 Konstantin Gredeskoul
module OpenLanes
  VERSION = "4.0.0"
end

# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes plans discard`
    class Discard < RemovalCommand
      desc "Take plans out of the active list, by deliberate decision"

      removes :discarded, "discarding"
    end
  end
end

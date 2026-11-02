# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes plans abandon`
    class Abandon < RemovalCommand
      desc "Take plans out of the active list, because work on them stopped"

      removes :abandoned, "abandoning"
    end
  end
end

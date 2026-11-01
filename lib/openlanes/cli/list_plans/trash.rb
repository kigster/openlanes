# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes plans trash`
    class Trash < RemovalCommand
      desc "Remove plans from the workspace: done elsewhere, never to be done, or to start over"

      removes :trashed, "trashing", choices: OpenLanes::Lifecycle::ReasonInterview::TRASH_CHOICES
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Plans
    # The note left in `abandoned/`, `discarded/` and `trashed/` (X1): the three
    # words are close enough that a person landing in one needs telling apart.
    module RemovedReadme
      FILENAME = "README.md"

      TEXT = <<~MARKDOWN
        # Plans taken out of the active list

        - **👎 Abandoned** (`abandoned/`): work stopped before the plan was completed, without a clear decision to cancel it. It might be resumed.
        - **❌ Discarded** (`discarded/`): someone deliberately decided the plan should not proceed. It is kept as a record of that decision.
        - **🚮 Trashed** (`trashed/`): removed from the workspace, because it is already done, will never be done, conflicts with another plan, or needs restarting from scratch.

        Each plan says why in `<state>-reason.md`. Delete that file and run `ol resync dirs` to bring the plan back.
      MARKDOWN

      module_function

      # @param dir [String] the directory the plan just moved into
      # @return [void]
      def ensure(dir)
        path = File.join(dir, FILENAME)
        File.write(path, TEXT) unless File.exist?(path)
      end
    end
  end
end

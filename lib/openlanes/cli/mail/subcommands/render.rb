# frozen_string_literal: true

module OpenLanes
  module CLI
    module Mail
      # `openlanes mail render` — the whole exchange, as Markdown, on STDOUT.
      #
      # The JSON is the record. This prints a view of it and writes no file,
      # so there is never a second copy in the plan folder to disagree with
      # the first.
      class Render < Base
        include Locating

        desc "Print a plan's whole mailbox as Markdown"

        option :plan, required: true, desc: "Which plan: NNN or NNN.MM"

        example [
          "--plan 003            # every message, with read or unread",
          "--plan 003 > mail.md  # keep a copy wherever you like"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          puts mailbox_for(options).render
        end
      end
    end
  end
end

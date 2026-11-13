# frozen_string_literal: true

module OpenLanes
  module CLI
    module Memory
      # `openlanes memory approve`
      class Approve < Base
        desc "Mark a waiting lesson for promotion whatever the number of plans it was seen in"

        argument :slug, required: true, desc: "The candidate's slug, as `openlanes memory inbox` lists it"

        example ["real-plan-trees-in-specs   # then `openlanes memory promote`"]

        # @return [void]
        def call(slug:, **)
          OpenLanes::Memory.inbox(root: Dir.pwd).approve(slug) or
            refuse("Nothing waits under #{slug}. `openlanes memory inbox` lists what does.", 66)
          warn("#{slug} approved. `openlanes memory promote` makes it a lesson.")
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # How a plan finished: staff-reviewer approved it, or its pull request merged.
      class Finish < Section
        # @return [OpenLanes::Plans::PlanState::Finished, nil]
        def finished
          record = read["finished"] or return nil
          Finished.new(kind: record["kind"], at: parse_time(record["at"]))
        end

        # A merge replaces an approval; nothing replaces a merge, so a watch
        # reporting the same merge on every poll keeps the first time.
        #
        # @param kind [String] one of {PlanState::FINISH_KINDS}
        # @param at [Time]
        # @return [OpenLanes::Plans::PlanState::Finished] the record kept
        # @raise [OpenLanes::Error] for a kind outside {PlanState::FINISH_KINDS}
        def finish!(kind, at)
          kind = kind.to_s
          raise Error, "a plan finishes #{FINISH_KINDS.join(" or ")}, not #{kind.inspect}" unless FINISH_KINDS.include?(kind)

          current = finished
          return current if current&.merged?

          keep(Finished.new(kind:, at:))
        end

        # Forget that the plan finished. Writes nothing when there was nothing.
        #
        # @return [void]
        def unfinish!
          return unless read.key?("finished")

          update { |data| data.delete("finished") }
        end

        private

        # @return [OpenLanes::Plans::PlanState::Finished] a merge already on disk, or +kept+
        def keep(kept)
          update do |data|
            existing = data["finished"]
            if existing && existing["kind"] == "merged"
              kept = Finished.new(kind: "merged", at: parse_time(existing["at"]))
            else
              data["finished"] = kept.to_json_h
            end
          end
          kept
        end
      end
    end
  end
end

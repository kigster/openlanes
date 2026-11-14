# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rename < Step
        # The first half of a pair to finish holds the plan at its `holds_at`,
        # but the folder is not renamed yet: its partner's prompt names the
        # folder by path, and renaming it under the partner sent every later
        # write to a folder that no longer existed (issue #172).
        class Holds < Step
          # @param target [Symbol] the state the pair holds at
          # @return [OpenLanes::Engine::Runner::Attempt]
          def hold(ordinal, target, attempt)
            holds[ordinal] = target
            attempt.with(note: "#{attempt.note}; holds at #{Plans::STATUS_BY_KEY.fetch(target)} once its partner settles")
          end

          # Applies a pair's held rename once no agent of the plan is running.
          # A discard throws the held work away, and a fenced plan is another
          # machine's to rename, so in both the hold is dropped instead.
          #
          # @param ordinal [String]
          # @return [void]
          def apply_hold(ordinal)
            return unless holds.key?(ordinal)
            return if running.any? { plan_of(it) == ordinal }

            target = holds.delete(ordinal)
            return if discarding.key?(ordinal) || fenced.include?(ordinal)

            subject = fresh_by(Plans::Ordinal.parse(ordinal)) or return
            subject.machine.may?(target) ? subject.machine.promote!(target) : dropped(subject, target, ordinal)
          end

          private

          def dropped(subject, target, ordinal)
            status = Plans::STATUS_BY_KEY.fetch(target)
            UI.log("hold at #{status} dropped: #{status.violation(subject)}", level: :warn, plan: ordinal)
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Poll < Step
        # Messages published to Redis, kept in their plan's `state.json`
        # unless that file already has them. Holds the stream's cursor and the
        # plans it still has mail pending for, from one tick to the next.
        class Mail < Step
          # Every plan with an agent running is drained, and so is every plan
          # the stream has mail for, running or not: a worktree's `mail send`
          # reaches the main checkout only through the stream, which forgets
          # it after an hour. A plan stays on the list until nothing of its
          # mail is left pending.
          #
          # A message is acked once it is kept, or once it proves it never can
          # be (no body, no single sender), since retrying an invalid message
          # every second for an hour would only repeat the log line. One whose
          # plan this checkout cannot find stays pending and is tried next tick.
          #
          # Only delivery: nothing here reads whether a message was acked by
          # its reader, and no assignment turns on it (D3). Redis going away
          # mid-run costs the drain, never the tick.
          #
          # @return [void]
          def drain_mail
            return if mail.nil? || runner.dry_run?

            found, @mail_cursor = mail.plans_since(@mail_cursor || "0")
            @mail_plans = (@mail_plans || Set.new) | found
            (running.map { plan_of(it).to_s } | @mail_plans.to_a).each { drain(it) }
          rescue Live::Unavailable, SystemCallError => e
            UI.log("mail not drained: #{e.message}", level: :warn)
          end

          private

          def drain(ordinal)
            pending = mail.drain(plan: ordinal, consumer: "harness") { |message| keep_mail(ordinal, message) }
            @mail_plans.delete(ordinal) if pending.empty?
          end

          # @param ordinal [String]
          # @param message [Hash]
          # @return [Boolean] whether the stream may forget it
          def keep_mail(ordinal, message)
            subject = fresh_by(ordinal) or return false
            Plans.mailbox(subject.feature.path).deliver(message)
            true
          rescue OpenLanes::Error => e
            UI.log("mail not kept: #{e.message}", level: :warn, plan: ordinal)
            true
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # How a pair talks: what `openlanes mail send` appends, what a drain
      # from Redis delivers (B4), and what `mail ack` marks read.
      class Messages < Section
        # @return [Array<Hash>]
        def messages = read["messages"]

        # Append one message and give it the next number. A second append
        # under the same command id, to the same reader, returns the first.
        #
        # @param message [OpenLanes::Plans::PlanState::Message]
        # @return [Hash]
        def message!(message)
          written = nil
          update do |data|
            written = replayed(data["messages"], message) and next

            number = [data["messages"].map { |m| m["number"] }.max.to_i, message.after].max + 1
            written = message.to_json_h(number)
            data["messages"] << written
          end
          written
        end

        # Keep a message that arrived with its number already given. Never
        # deduped by number alone; a different message whose number is taken
        # is kept under the next free one.
        #
        # @param message [Hash] string keys
        # @param reserved [Array<Integer>] numbers taken by mailbox.md
        # @return [Hash, nil] the message as written, nil when it was here
        def deliver!(message, reserved)
          return nil if seen?(messages, message)

          delivered = nil
          update do |data|
            next if seen?(data["messages"], message)

            delivered = renumbered(message, data["messages"].map { |m| m["number"].to_i } + reserved)
            data["messages"] << delivered
            data["messages"].sort_by! { |m| m["number"].to_i }
          end
          delivered
        end

        # Mark one message read. Only its recipient may ack it.
        #
        # @param number [Integer]
        # @param by [String]
        # @return [Hash, nil] the message as written, nil when there is no such number
        # @raise [OpenLanes::Error] when +by+ is not the recipient
        def ack!(number, by)
          message = nil
          update do |data|
            message = data["messages"].find { |m| m["number"] == number } or next
            raise Error, "message ##{number} is for #{message["to"]}, not #{by}" unless message["to"] == by

            message["read"] = "yes"
          end
          message
        end

        private

        # @return [Hash, nil] the message an earlier append of the same command wrote
        def replayed(messages, message)
          message.command && messages.find { |m| m["command"] == message.command && m["to"] == message.to }
        end

        # @return [Boolean]
        def seen?(messages, message) = messages.any? { |m| same_message?(m, message) }

        # Unread whatever it arrived saying: only `mail ack` in this file says
        # its reader read it.
        #
        # @return [Hash]
        def renumbered(message, taken)
          number = taken.include?(message["number"]) ? taken.max + 1 : message["number"]
          message.slice("id", "number", "at", "from", "to", "body", "command").merge("number" => number, "read" => "no")
        end

        # @return [Boolean] whether the two are one message, by id when both
        #   carry one, by what they say otherwise
        def same_message?(one, other)
          return one["id"] == other["id"] if one["id"] && other["id"]

          %w[from to body].all? { one[it] == other[it] } && parse_time(one["at"]) == parse_time(other["at"])
        end
      end
    end
  end
end

# frozen_string_literal: true

module OpenLanes
  module Plans
    class PlanState
      # How a pair talks: what `openlanes mail send` appends, what a drain
      # from Redis delivers (B4), and what `mail ack` marks read.
      class Messages < Section
        # @return [Array<Hash>]
        def messages = read["messages"]

        # Append one message and give it the next number. A command is applied
        # at least once (W13), so a second append under the same command id, to
        # the same reader, returns the first and adds nothing: an engine that
        # died between the append and recording the reply does not say the
        # same thing twice.
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

        # Keep a message that arrived with its number already given, as one
        # drained from Redis does (B4).
        #
        # A message is the same message when its id matches, or, when either
        # side was written before ids existed, when sender, recipient, time and
        # body all match. Never by number alone: `mail send` in a worktree
        # numbers against the worktree's `state.json`, the main checkout
        # numbers against its own, and both can hand out #4. Deduping on the
        # number dropped the second #4 as a "duplicate" without a word.
        #
        # So the usual case, `mail send` having already written here before it
        # published, writes nothing at all and the file's mtime stays; and a
        # different message whose number is taken is kept under the next free
        # one.
        #
        # @param message [Hash] as {#message!} writes it, string keys
        # @param reserved [Array<Integer>] numbers taken outside this file,
        #   i.e. by mailbox.md
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

        # Mark one message read, under the lock, so an ack and a send in the
        # same second cannot lose each other. Only its recipient may ack it:
        # `read` says the reader read it, not that somebody did.
        #
        # @param number [Integer]
        # @param by [String] the agent acking, who must be the recipient
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

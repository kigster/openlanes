# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes slack …`
    module Slack
      # `slack test` — the whole round trip, without an engine or a blocked
      # plan: is the token good, is it the right workspace, can the app post
      # to the channel, and does an answer given there come back. Everything
      # a run does with Slack it does through the same {OpenLanes::Slack::Room},
      # so a test that passes here is the run's path, not a likeness of it.
      class Test < Base
        desc "Post a sample poll to the project's Slack channel and wait for an answer"

        option :timeout, type: :integer, default: 120, desc: "Seconds to wait for somebody to answer"

        example [
          "                  # post the poll, wait two minutes",
          "--timeout 600     # wait ten"
        ]

        # The plan the sample question claims to come from.
        PLAN = { "ordinal" => "000.00", "title" => "Connection Test" }.freeze

        # The sample question, shaped as the engine's snapshot shapes a real one.
        QUESTION = {
          "id" => "000.00/B1", "kind" => "block", "owner" => "technical", "agent" => "openlanes",
          "heading" => "B1 — Is the Slack connection working?",
          "body" => "This is a test from `openlanes slack test`. Nothing is blocked, and no plan is changed by your answer.",
          "options" => [
            { "letter" => "a", "label" => "Yes, I can see this", "recommended" => true, "answer" => "a) Yes, I can see this" },
            { "letter" => "b", "label" => "No (but then how are you reading it?)", "recommended" => false, "answer" => "b) No" }
          ]
        }.freeze

        # @param options [Hash]
        # @return [void]
        def call(**options)
          room = OpenLanes::Slack.room
          poll = OpenLanes::Slack::Poll.new(plan: PLAN, question: QUESTION)
          ref = ask(room, poll)
          say("Posted. React to it or reply in its thread; waiting #{options[:timeout]}s.")

          vote = await(room, ref, poll, options[:timeout].to_i) or return unanswered(room, ref, poll)
          room.close(ref, poll, ":white_check_mark: Answered by <@#{vote.user}>: #{vote.label}")
          puts "#{room.name_of(vote.user)}\t#{vote.text}"
        rescue OpenLanes::Error => e
          refuse(e.message, 69)
        end

        private

        # Say whose token this is before anything is posted with it.
        #
        # @return [OpenLanes::Slack::Room::Ref]
        def ask(room, poll)
          who = room.identity
          say("Workspace #{paint(who["team"].to_s, :cyan)} (#{who["team_id"]}), posting as #{who["user"]} to #{room.channel}")
          room.post(poll).tap { room.decorate(it, poll) }
        end

        # @return [OpenLanes::Slack::Poll::Vote, nil] nil when the time ran out
        def await(room, ref, poll, timeout)
          deadline = UI.monotonic + timeout
          loop do
            vote = room.vote(ref, poll) and return vote
            return nil if UI.monotonic >= deadline

            Kernel.sleep(OpenLanes::Slack::DEFAULT_INTERVAL)
          end
        end

        # The post worked and the read did not fail, so the likely cause is
        # a person, not a scope; say which it would be if it were a scope.
        #
        # @return [void]
        def unanswered(room, ref, poll)
          room.close(ref, poll, "Nobody answered in time.")
          refuse("The poll was posted, and nobody answered it in time. If you did answer, the app is missing a scope " \
                 "it reads answers with: reactions:read, and channels:history (groups:history for a private channel).",
            75)
        end
      end
    end
  end
end

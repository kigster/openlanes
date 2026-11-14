# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      class Rename < Step
        # Push the build and open, or update, its pull request, before the
        # folder is asked whether it may move to 🟢.
        #
        # The order is the whole point. 🟢 is justified by an open pull request
        # recorded in `pull-requests.md`, and only the publisher records one.
        # Promoting first and publishing after, as this once did, failed every
        # first build under worktree isolation, and no plan ever reached
        # review. This runs in settle, after the executor's own boundary check:
        # the commit and push are the harness's, never mistaken for the agent's.
        class Publication < Step
          # @param task [OpenLanes::Engine::Runner::Task]
          # @param target [Symbol]
          # @param subject [OpenLanes::Plans::Subject] the plan, read fresh
          # @param attempt [OpenLanes::Engine::Runner::Attempt]
          # @return [OpenLanes::Engine::Dispatcher::Published]
          def call(task, target, subject, attempt)
            unchanged = Published.new(attempt:, subject:, refused: false)
            return unchanged unless target == :ready_for_review

            publication = runner.publish(task, subject)
            return refused(publication, subject, attempt) if publication&.refusal
            return unchanged unless publication&.published?

            published(task, publication, subject, attempt)
          end

          private

          def refused(publication, subject, attempt)
            Published.new(attempt: attempt.with(ok: false, note: "#{attempt.note}; publish refused: #{publication.refusal}"),
              subject:,
              refused: true,
              untestable: publication.untestable?)
          end

          # Once per refusal, not once per run: a later round that loses the
          # section again is owed another mail rather than a silent Interrupted.
          def published(task, publication, subject, attempt)
            mutex.synchronize { asked_how_to_test.delete(task.subject.feature.ordinal.to_s) }
            note = "#{attempt.note}; #{publication.updated ? "pushed to" : "opened"} #{publication.url}"
            note += unlabelled(publication) if publication.label_error
            Published.new(attempt: attempt.with(note:), subject: fresh(task) || subject, refused: false)
          end

          def unlabelled(publication)
            label = publication.updated ? Plans::ReviewLabel::ADDRESSED : Plans::ReviewLabel::INITIAL
            "; #{label} not applied: #{publication.label_error}"
          end
        end
      end
    end
  end
end

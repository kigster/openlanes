# frozen_string_literal: true

module OpenLanes
  module Engine
    class Dispatcher
      # Where a plan's folder goes once a round has signed for itself: on to
      # the state the agent advances to, held for a partner, back for a
      # rejection, or into ⭕ for a question. The build is published before
      # the folder is asked whether it may move to 🟢, and a reviewer's or
      # verifier's verdict is counted before anything moves at all.
      #
      # {Settle} decides that a round ended Completed or Blocked; what that
      # does to the folder is decided here, and nowhere else.
      class Rename < Step
        # What a builder is told when its finished work has no way to be tested.
        HOW_TO_TEST_MAIL = <<~MAIL.freeze
          The build is done, but the pull request was not opened: plan.md has no
          `#{Lifecycle::Completion::HOW_TO_TEST}` section, and a pull request nobody can test is not
          ready for review. Add one to plan.md: the commands to run and what a person
          should see, as a list, covering every part of the build and not only yours.
          Change nothing else, then sign Completed again.
        MAIL

        # `starts_as`: the folder moves the moment the agent is dispatched, where
        # the topology allows, so backend-coder's start is what makes a plan 🟡.
        #
        # @return [OpenLanes::Plans::Subject] fresh, under whichever name it now has
        def rename_on_start(subject, agent)
          target = agent.starts_as
          return subject unless target && subject.machine.may?(target)

          subject.machine.promote!(target)
          Plans::Tree.new(dir: runner.tree.dir).find(subject.feature.ordinal) || subject
        end

        # A Completed entry: publish if the move is to 🟢, then move the folder,
        # and honour the `next:` line.
        #
        # @return [OpenLanes::Engine::Runner::Attempt]
        def complete(job, base, entry, reading)
          task = job.task
          agent = task.agent
          ordinal = task.subject.feature.ordinal.to_s
          subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
          remember(ordinal, agent.name, job.state, "Completed", task.round)
          Lifecycle::Completion.copy(subject) if agent.ledger.include?("plan.md")
          # Only a reviewer rules. A builder that signed `Completed (approved)`
          # once had its own work taken as approved: the plan was parked as
          # finished at 🟡, never reviewed and never published.
          return assessed(job, base, entry.note) if assessor?(agent)

          if agent.phase.to_s == REVIEW_PHASE
            decision = reviewed(job, subject, entry) or return unvoted(job, base)
            return base.with(status: "Completed", note: "#{base.note}; #{decision.note}") if decision.pending?

            base = base.with(note: "#{base.note}; #{decision.note}")
            verdict = decision.target
          end
          verdict = verdict_of(entry) if agent.phase.to_s == Verification::PHASE
          return verified(job, base, subject, verdict) if agent.phase.to_s == Verification::PHASE && runner.verification

          partner_running = running.any? { |j| j.task.subject.feature.ordinal.to_s == ordinal }
          target = target_for(agent, verdict, partner_running)

          return approved(job, base, subject, ordinal) if verdict == :approved
          return built_locally(base.with(status: "Completed"), ordinal) if verdict == :verified

          attempt = base.with(status: "Completed")
          return built_locally(attempt, ordinal) if local_only_review?(target, subject)

          if target && partner_running && target == agent.holds_at
            attempt = hold(ordinal, target, attempt)
          elsif target
            attempt = attempt.with(note: "#{base.note}#{" (#{entry.note})" if entry.note}")
            published = publish_for_review(task, target, subject, attempt)
            return untestable(job, published.attempt, subject) if published.untestable
            return unpublished(published, ordinal) if published.refused

            attempt = published.attempt
            subject = published.subject
            target = subject.machine.onward(target)
            return unjustified(job, attempt, subject, target) unless subject.machine.may?(target)

            subject.machine.promote!(target)
            attempt = attempt.with(to: target)
          end

          handoff = Plans::Ledger.handoff_after(reading, entry)
          attempt = honour(handoff, subject, attempt) if handoff
          attempt
        end

        # @return [OpenLanes::Engine::Runner::Attempt]
        def park(job, base, entry)
          task = job.task
          subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
          remember(subject.feature.ordinal.to_s, task.agent.name, job.state, "Blocked", task.round)
          target = verdict_of(entry) == :product ? :product_blocked : :blocked
          feed.append(:question, plan: subject.feature.ordinal.to_s, agent: task.agent.name, note: target.to_s)
          if subject.machine.may?(target)
            subject.machine.promote!(target)
            base.with(to: target, status: "Blocked", note: "blocked; see blocked.md")
          else
            base.with(ok: false, status: "Blocked", note: "ledger says Blocked but #{Plans::STATUS_BY_KEY.fetch(target).violation(subject)}")
          end
        end

        # deploy-assessor finished, or stopped without a verdict. The engine labels,
        # merges and rebases from here; the folder moves only to ✅ or 🔴.
        #
        # @param note [String, nil] the Completed note; nil reads as `manual`
        # @return [OpenLanes::Engine::Runner::Attempt]
        def assessed(job, base, note)
          task = job.task
          subject = fresh(task) or return base.with(ok: false, note: "plan folder vanished")
          remember(plan_of(job), task.agent.name, job.state, "Completed", task.round)
          result = runner.merging.assess(subject, note)
          wake!
          base.with(status: "Completed", to: result.to || job.state, note: "#{base.note}; #{result.note}")
        rescue OpenLanes::Error => e
          base.with(ok: false, status: "Completed", note: "#{base.note}; merge not settled: #{e.message}")
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
          if subject.machine.may?(target)
            subject.machine.promote!(target)
          else
            UI.log("hold at #{Plans::STATUS_BY_KEY.fetch(target)} dropped: #{Plans::STATUS_BY_KEY.fetch(target).violation(subject)}",
              level: :warn,
              plan:  ordinal)
          end
        end

        private

        # A reviewer's verdict, counted with the rest of its round (plan 031,
        # D4 to D7). The verdict goes on the reviewer's stage first, so a
        # restart still counts it; the pull request is labelled only once the
        # last reviewer has spoken, and only by the engine.
        #
        # @param job [OpenLanes::Engine::Dispatcher::Job]
        # @param subject [OpenLanes::Plans::Subject]
        # @param entry [OpenLanes::Plans::Ledger::Entry]
        # @return [OpenLanes::Engine::Reviews::Decision, nil] nil when the
        #   note reports no verdict
        def reviewed(job, subject, entry)
          task = job.task
          reviews = runner.reviews
          others = running.reject { it.equal?(job) }.select { plan_of(it) == plan_of(job) }.map { it.task.agent.name }
          decision = reviews.decide(subject, task.agent, entry.note.to_s, running: others) or return

          reviews.vote!(subject, task.agent, task.round, entry.note.to_s)
          decision.pending? ? decision : reviews.conclude(subject, decision)
        end

        # A reviewer signed Completed without a verdict. Moving the plan on
        # that once took silence for approval; the round fails instead, so the
        # reviewer runs again while it has rounds left.
        #
        # @return [OpenLanes::Engine::Runner::Attempt]
        def unvoted(job, base)
          task = job.task
          remember(plan_of(job), task.agent.name, job.state, "Interrupted", task.round)
          base.with(ok: false, status: "Interrupted", note: "#{base.note}; signed no verdict: great, passed, rejected or slop")
        end

        # The agent signed Completed, but what it left does not justify the
        # state it advances to. The folder stays, its `next:` is not honoured,
        # and the round is recorded as Interrupted; once the agent's rounds run
        # out, Needs you asks for more of them (E1). Taking the
        # signature at its word instead parked the plan: nobody else handles
        # the state it is still in, and its own agent counted itself done.
        #
        # @return [OpenLanes::Engine::Runner::Attempt]
        def unjustified(job, attempt, subject, target)
          status = Plans::STATUS_BY_KEY.fetch(target)
          remember(plan_of(job), job.task.agent.name, job.state, "Interrupted", job.task.round)
          attempt.with(ok: false,
            status: "Interrupted",
            note: "ledger says Completed but #{status} is not justified: #{status.violation(subject)}")
        end

        # A build finished in a run that opens no pull request: 🟢 needs one,
        # so the folder cannot move, and failing the attempt would only start
        # the builder again on work that is done. Only the missing pull request
        # is forgiven, and pull-requests.md with it, where the pull request
        # would be recorded: a build that deleted another file 🟢 requires
        # (spec.md, plan.md) is still reported, rather than parked as done. 🟡's own
        # invariant is not asked, since a quick-lane plan.md has no work units.
        #
        # @param target [Symbol, nil]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [Boolean]
        def local_only_review?(target, subject)
          return false unless target == :ready_for_review && !runner.publishes? && !subject.machine.may?(target)

          (Plans::STATUS_BY_KEY.fetch(target).requires - %w[pull-requests.md]).all? { subject.file?(it) }
        end

        # The build stays at 🟡, finished for this run, saying why.
        #
        # @param attempt [OpenLanes::Engine::Runner::Attempt]
        # @param ordinal [String]
        # @return [OpenLanes::Engine::Runner::Attempt]
        def built_locally(attempt, ordinal)
          finished_plans << ordinal
          attempt.with(note: "#{attempt.note}; built locally, no pull request in this run, so it waits for one")
        end

        # staff-reviewer approved. Into 🧪 when the run verifies and the pull request
        # carries a verdict that goes on to verification; otherwise the plan is
        # finished at 👀, as it was before verifier existed. A 🔴 or, under
        # `standard`, a 🟡 after the hand-off is the hand-off's own send-back,
        # signed as one so the ledger does not call a return to 🟡 "approved".
        #
        # @return [OpenLanes::Engine::Runner::Attempt]
        def approved(job, base, subject, ordinal)
          record_approval(job, subject)
          said = runner.verification&.hand_off(subject)
          now = fresh_by(ordinal)&.status&.key
          if %i[verifying rejected building].include?(now)
            word = now == :verifying ? "approved" : "sent back"
            return base.with(status: "Completed", to: now, note: "#{base.note}; #{word}, #{said}")
          end

          finished_plans << ordinal
          finish(subject, "approved")
          base.with(status: "Completed", note: "#{base.note}; approved, awaiting merge#{"; #{said}" if said}")
        end

        # The approval goes into the event log as the `pr_reviewed` a person's
        # rejection is recorded as, or the report would count reviews from
        # rejections alone. The watch never sees an approval (only the merge
        # after it), so the reviewer's verdict is where it is known. Keyed by
        # the round, so a PR approved again after a fix cycle is a second
        # review, and a restarted round noticing the same signing is not.
        # A plan with no open pull request has nothing to count it against.
        #
        # @return [void]
        def record_approval(job, subject)
          pull = subject.pull_requests.find(&:open?) or return
          number = pull.number.to_s.delete("#").to_i
          runner.events.record(:pr_reviewed,
            plan:    subject.feature.ordinal.to_s,
            seq:     [number, "approved", job.task.round],
            once:    true,
            number:,
            verdict: "approved")
        end

        # verifier signed. The engine commits, comments and labels from its
        # report; the folder moves only on a rejection.
        #
        # @return [OpenLanes::Engine::Runner::Attempt]
        def verified(job, base, subject, verdict)
          driver = runner.verification
          result = case verdict
                   when :rejected then driver.reject(job.task, subject)
                   when :verified then driver.pass(job.task, subject)
                   end
          return base.with(ok: false, status: "Completed", note: "#{base.note}; signed neither verified nor rejected") unless verdict
          return base.with(ok: false, status: "Completed", note: "#{base.note}; no open pull request to verify") unless result

          wake!
          base.with(status: "Completed", to: result.to || job.state, note: "#{base.note}; #{result.note}")
        end

        # @param entry [OpenLanes::Plans::Ledger::Entry]
        # @return [Symbol, nil] :rejected, :verified, :approved, :slop, :product or nil
        def verdict_of(entry)
          note = entry.note.to_s.downcase
          # Anchored, as the rejection count is: "nothing to reject" approves.
          return :rejected if note.strip.match?(Verification::Outcome::REJECTION)
          return :verified if note.include?("verified")
          return :approved if note.include?("approv")
          return :slop if note.include?("slop") || note.include?("rewrite")
          return :product if note.include?("product")

          nil
        end

        # The first half of a pair to finish holds the plan at its `holds_at`,
        # but the folder is not renamed yet: its partner's prompt names the
        # folder by path, and renaming it under the partner sent every later
        # write to a folder that no longer existed (issue #172). The hold is
        # applied by {#apply_hold} once the last agent of the plan is reaped.
        #
        # @param ordinal [String]
        # @param target [Symbol] the state the pair holds at
        # @param attempt [OpenLanes::Engine::Runner::Attempt]
        # @return [OpenLanes::Engine::Runner::Attempt]
        def hold(ordinal, target, attempt)
          holds[ordinal] = target
          attempt.with(note: "#{attempt.note}; holds at #{Plans::STATUS_BY_KEY.fetch(target)} once its partner settles")
        end

        # @return [Symbol, nil] where the folder goes
        def target_for(agent, verdict, partner_running)
          case verdict
          when :rejected then :rejected
          when :slop then :rewrite
          else partner_running ? agent.holds_at : agent.advances_to
          end
        end

        # Push the build and open, or update, its pull request, before the
        # folder is asked whether it may move to 🟢.
        #
        # The order is the whole point. 🟢 is justified by an open pull request
        # recorded in `pull-requests.md`, and only the publisher records one.
        # Promoting first and publishing after, as this once did, asked the
        # invariant a question only the publish could answer: every first build
        # under worktree isolation failed with "Ready for Review requires an open
        # pull request; none are recorded", and no plan ever reached review.
        #
        # This runs in settle, after the executor's own boundary check has
        # already compared HEAD against where the agent started. The commit and
        # push are the harness's, so they cannot be mistaken for the agent's.
        #
        # @param task [OpenLanes::Engine::Runner::Task]
        # @param target [Symbol]
        # @param subject [OpenLanes::Plans::Subject] the plan, read fresh
        # @param attempt [OpenLanes::Engine::Runner::Attempt]
        # @return [OpenLanes::Engine::Dispatcher::Published]
        def publish_for_review(task, target, subject, attempt)
          unchanged = Published.new(attempt:, subject:, refused: false)
          return unchanged unless target == :ready_for_review

          publication = runner.publish(task, subject)
          if publication&.refusal
            Published.new(attempt: attempt.with(ok: false, note: "#{attempt.note}; publish refused: #{publication.refusal}"),
              subject:,
              refused:    true,
              untestable: publication.untestable?)
          elsif publication&.published?
            # Once per refusal, not once per run: a later round that loses the
            # section again is owed another mail rather than a silent Interrupted.
            mutex.synchronize { asked_how_to_test.delete(task.subject.feature.ordinal.to_s) }
            verb = publication.updated ? "pushed to" : "opened"
            note = "#{attempt.note}; #{verb} #{publication.url}"
            if publication.label_error
              label = publication.updated ? Plans::ReviewLabel::ADDRESSED : Plans::ReviewLabel::INITIAL
              note += "; #{label} not applied: #{publication.label_error}"
            end
            Published.new(attempt: attempt.with(note:), subject: fresh(task) || subject, refused: false)
          else
            unchanged
          end
        end

        # The builders finished, but plan.md says nothing about how to test the
        # result. That is work an agent can do, so the builder is mailed what is
        # missing and handed its round back, once, to write it. A second refusal
        # is Interrupted and spends a round, as any failed round does. Parking the plan
        # as finished, as a rejected push is, left 021 at 🟡 with nothing on the
        # page saying why.
        #
        # @param job [Job]
        # @param attempt [OpenLanes::Engine::Runner::Attempt]
        # @param subject [OpenLanes::Plans::Subject]
        # @return [OpenLanes::Engine::Runner::Attempt]
        def untestable(job, attempt, subject)
          agent = job.task.agent
          ordinal = plan_of(job)
          if mutex.synchronize { asked_how_to_test.add?(ordinal) }
            forget_round(job)
            Plans::Mailbox.new(dir: subject.feature.path).append(from: HARNESS, to: agent.name, body: HOW_TO_TEST_MAIL)
            return attempt.with(status: "Interrupted", note: "#{attempt.note}; #{agent.name} was asked to add it")
          end

          remember(ordinal, agent.name, job.state, "Interrupted", job.task.round)
          attempt.with(status: "Interrupted", note: "#{attempt.note}; still missing after #{agent.name} was asked")
        end

        # A refused publish leaves the plan where it was. Running the builder
        # again would redo finished work to hit the same rejected push, so the
        # plan is done for this run and the attempt says why.
        #
        # @param published [OpenLanes::Engine::Dispatcher::Published]
        # @param ordinal [String]
        # @return [OpenLanes::Engine::Runner::Attempt]
        def unpublished(published, ordinal)
          finished_plans << ordinal
          published.attempt
        end

        # A `next:` that names someone who handles the plan's new state is
        # honoured by preferring them; one that does not is reported, and the
        # state's own agents take it, because a wrong name must not stall a plan.
        #
        # @return [OpenLanes::Engine::Runner::Attempt]
        def honour(handoff, subject, attempt)
          current = fresh_by(subject.feature.ordinal) || subject
          named = runner.agents.find(handoff.next)
          if named&.handles?(current.status)
            preferred_agents[current.feature.ordinal.to_s] = named.name
            attempt
          else
            who = named ? "does not handle #{current.status}" : "is not an agent"
            attempt.with(note: "#{attempt.note}; next: names #{handoff.next}, who #{who}")
          end
        end
      end
    end
  end
end

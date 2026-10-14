# frozen_string_literal: true

require "json"
require "yaml"

module OpenLanes
  module Live
    # The engine's side of the command stream (W13). Called at the top of
    # every tick, on the loop thread, it reads what the page sent through the
    # `engine` consumer group, applies each command to the dispatcher, and
    # answers it.
    #
    # Delivery is at least once: a command is acknowledged only after it has
    # been applied, in the same `MULTI` that records its reply in `done` and
    # appends it to `replies`. A command whose id is already in `done` was
    # applied before the engine died, so it is acknowledged and its first
    # reply sent again, and nothing is applied twice.
    #
    # Each kind is one method, named in {HANDLERS}. A handler raises
    # {Refusal} with the reason a person will read; anything it returns is
    # a reason to show beside "done".
    class Commands
      # A command the engine will not apply, with the reason why.
      class Refusal < StandardError; end

      # Commands read per tick, so a flood cannot hold the loop.
      BATCH = 50

      # Seconds between sweeps of `done` for entries older than a day.
      SWEEP_EVERY = 600

      # Command kind to the method that applies it.
      HANDLERS = {
        "answer"       => :answer,
        "hold_blocked" => :hold_blocked,
        "release_hold" => :release_hold,
        "resume"       => :resume,
        "discard"      => :discard,
        "message"      => :message,
        "hold"         => :signal,
        "wrap_up"      => :signal,
        "compact"      => :compact,
        "stop"         => :signal,
        "stop_all"     => :stop_all,
        "set_model"    => :set_model,
        "switch_model" => :switch_model,
        "add_plan"     => :add_plan,
        "create_plans" => :create_plans
      }.freeze

      # Plans a person may not add to a run: there is nothing left to do.
      FINISHED = Snapshot::FINISHED

      # @param store [OpenLanes::Live::Store, OpenLanes::Live::MemoryStore]
      # @param keys [OpenLanes::Live::Keys]
      # @param node [OpenLanes::Live::Node]
      # @param run_state [OpenLanes::Live::RunState]
      # @param record [OpenLanes::Live::RunRecord, nil] writes the run state
      #   in the same `MULTI` as each reply
      # @param claims [OpenLanes::Live::Claims, nil]
      # @param clock [Proc] wall time
      def initialize(store:, keys:, node:, run_state: RunState.new, record: nil, claims: nil, clock: -> { Time.now })
        @store = store
        @keys = keys
        @node = node
        @run_state = run_state
        @record = record
        @claims = claims
        @clock = clock
        @ready = false
        @swept_at = nil
        @pending = {}
      end

      # Apply everything waiting: this consumer's unacknowledged commands
      # first, which a previous engine read and died on, then new ones.
      #
      # @param dispatcher [OpenLanes::Engine::Dispatcher]
      # @return [Array<OpenLanes::Live::Reply>] what was answered
      def call(dispatcher)
        prepare
        replies = collect
        entries = read("0").reject { @pending.key?(it.id) }
        entries += read(">") if entries.size < BATCH
        replies += entries.filter_map { |entry| handle(entry, dispatcher) }
        # Whatever a command changed is acted on this tick, not at the end
        # of an idle run's rescan interval.
        dispatcher.wake! unless entries.empty? && replies.empty?
        sweep
        replies
      rescue Unavailable => e
        UI.log("commands not read: #{e.message}")
        []
      end

      # @return [Proc] for {Engine::Dispatcher#before_tick}
      def to_proc = method(:call).to_proc

      private

      # @return [void]
      def prepare
        return if @ready

        @store.xgroup_create(@keys.commands, Keys::GROUP, from: "0")
        @ready = true
      end

      # @param id [String] "0" for this consumer's pending, ">" for new
      # @return [Array<OpenLanes::Live::Store::Entry>]
      def read(id) = @store.xreadgroup(@keys.commands, Keys::GROUP, @node.name, id:, count: BATCH)

      # Answer the commands whose work finished since the last tick. A
      # command still at work is neither answered nor acknowledged, so an
      # engine that dies meanwhile gets it again.
      #
      # @return [Array<OpenLanes::Live::Reply>]
      def collect
        @pending.select { |_, (_, _, work)| work.finished? }.map do |entry_id, (entry, id, work)|
          @pending.delete(entry_id)
          reply(entry, id, work.status, work.reason)
        end
      end

      # @param entry [OpenLanes::Live::Store::Entry]
      # @param dispatcher [OpenLanes::Engine::Dispatcher]
      # @return [OpenLanes::Live::Reply, nil] nil while the command is still at work
      def handle(entry, dispatcher)
        command = Command.parse(entry.fields["json"].to_s)
        if (first = @store.hget(@keys.done, command.id))
          return answer_again(entry, first)
        end

        # Said on the terminal and in the log: what a person asked for from
        # the page is part of the run's story, beside what the agents did.
        UI.log("from the page: #{command.kind.tr("_", " ")}", **{ plan: command.plan, agent: command.agent }.compact)
        status, reason = apply(command, dispatcher)
        return reply(entry, command.id, status, reason) unless status == :pending

        @pending[entry.id] = [entry, command.id, reason]
        nil
      rescue Command::Invalid => e
        reply(entry, invalid_id(entry), "refused", e.message)
      end

      # @return [Array(String, String)] status and reason, or `:pending` and
      #   the work still under way
      def apply(command, dispatcher)
        reason = send(HANDLERS.fetch(command.kind), command, dispatcher)
        return [:pending, reason] if reason.respond_to?(:finished?)

        ["done", reason.is_a?(String) ? reason : nil]
      rescue Refusal, OpenLanes::Error => e
        ["refused", e.message]
      rescue StandardError => e
        UI.log("#{command.kind} failed: #{e.class}: #{e.message}", plan: command.plan)
        ["refused", "#{command.kind} failed: #{e.message}"]
      end

      # @return [OpenLanes::Live::Reply]
      def reply(entry, id, status, reason)
        reply = Reply.new(id:, status:, reason:, at: @clock.call)
        json = reply.to_json
        @store.multi do |tx|
          tx.hset(@keys.done, id, json)
          tx.xadd(@keys.replies, { json: }, maxlen: Keys::REPLIES_LENGTH)
          tx.xack(@keys.commands, Keys::GROUP, entry.id)
          @record&.write(tx)
        end
        reply
      end

      # @return [OpenLanes::Live::Reply] the first reply, sent again
      def answer_again(entry, first)
        @store.multi do |tx|
          tx.xadd(@keys.replies, { json: first }, maxlen: Keys::REPLIES_LENGTH)
          tx.xack(@keys.commands, Keys::GROUP, entry.id)
        end
        data = JSON.parse(first)
        Reply.new(id: data["id"], status: data["status"], reason: data["reason"], at: Time.iso8601(data["at"]))
      end

      # A command too malformed to carry an id is answered under its stream
      # entry's id, so the reply still lands somewhere a person can see.
      #
      # @return [String]
      def invalid_id(entry)
        id = JSON.parse(entry.fields["json"].to_s)["id"].to_s
        id.match?(Command::ID) ? id : entry.id
      rescue JSON::ParserError, TypeError, NoMethodError
        entry.id
      end

      # Forget replies older than {Keys::DONE_TTL}; a command redelivered a
      # day late has bigger problems than being applied twice.
      #
      # @return [void]
      def sweep
        now = @clock.call
        return if @swept_at && now - @swept_at < SWEEP_EVERY

        @swept_at = now
        stale = @store.hgetall(@keys.done).reject { |_, json| (at = reply_time(json)) && now - at <= Keys::DONE_TTL }
        @store.hdel(@keys.done, *stale.keys)
      end

      # @param json [String] a reply in `done`
      # @return [Time, nil] when it was answered; nil for an entry nothing can
      #   read, which the sweep removes rather than letting it stop the sweep
      def reply_time(json)
        Time.iso8601(JSON.parse(json).fetch("at"))
      rescue JSON::ParserError, ArgumentError, TypeError, KeyError, NoMethodError
        nil
      end

      # ---- questions --------------------------------------------------------

      # `## A<n>` under the question, signed, for `lando-broker` to fold in
      # (W10). The dispatcher hands the plan to the broker once every
      # question has an answer, and the plan leaves ⭕️ when the file is
      # drained. The answer carries the command's id in a comment, so a
      # command applied again after a crash finds it and writes nothing.
      #
      # @return [String, nil]
      def answer(command, dispatcher)
        subject, question = question!(command, dispatcher)
        path = File.join(subject.feature.path, "blocked.md")
        return nil if File.read(path).include?(marker(command))
        return "B#{question.number} already has an answer waiting" if question.answered

        File.open(path, "a") do |file|
          file.write("\n## A#{question.number}\n\n#{command["text"]}\n\n" \
                     "Answered by #{@node.user} on #{@clock.call.strftime("%Y-%m-%d")}\n#{marker(command)}\n")
        end
        @run_state.hold_question(question_id(subject, question), held: false)
        dispatcher.wake!
        nil
      end

      # @return [nil]
      def hold_blocked(command, dispatcher) = hold_question(command, dispatcher, held: true)

      # @return [nil]
      def release_hold(command, dispatcher) = hold_question(command, dispatcher, held: false)

      # @return [nil]
      def hold_question(command, dispatcher, held:)
        subject, question = question!(command, dispatcher)
        @run_state.hold_question(question_id(subject, question), held:)
        nil
      end

      # @return [Array(OpenLanes::Plans::Subject, OpenLanes::Lifecycle::Unblocker::Question)]
      def question!(command, dispatcher)
        subject = subject!(command, dispatcher)
        number = command["question"][/\AB?(\d+)\z/i, 1] or raise Refusal, "#{command["question"]} is not a question number like B2"
        question = Lifecycle::Unblocker.questions(subject).find { it.number == number.to_i } or
          raise Refusal, "#{command.plan} has no open question B#{number}"
        [subject, question]
      end

      # @return [String]
      def question_id(subject, question) = "#{subject.feature.ordinal}/B#{question.number}"

      # ---- agents -----------------------------------------------------------

      # The agent the plan's history says was interrupted is started again,
      # with the person's note waiting in its mailbox.
      #
      # @return [String]
      def resume(command, dispatcher)
        subject = subject!(command, dispatcher)
        last = Plans::PlanState.for(subject.feature.path).stages.rfind { it["status"] == "Interrupted" }
        agent = command.agent.to_s.empty? ? last&.fetch("agent", nil) : command.agent
        raise Refusal, "#{command.plan} has no interrupted agent to resume" unless agent

        note = command["note"].empty? ? "carry on from your last resume note" : command["note"]
        Plans::Mailbox.new(dir: subject.feature.path).append(from: "human",
          to: agent,
          body: "RESUME: #{note}",
          command: command.id)
        dispatcher.resume(subject.feature.ordinal, agent)
        dispatcher.runner.add_plan(subject.feature.ordinal)
        dispatcher.wake!
        "#{agent} resumes on #{command.plan} at its next turn"
      end

      # Plan-wide (W9): every agent on the plan stops, its worktree is reset,
      # and the folder goes back one state. The reply waits for all three.
      #
      # @return [OpenLanes::Engine::Dispatcher::Discard] still at work
      def discard(command, dispatcher)
        subject = subject!(command, dispatcher)
        dispatcher.discard(subject.feature.ordinal)
      end

      # A person's message, into the plan's mailbox, from `human` (W10). To
      # the agent named, or every agent working the plan when none is. Each
      # entry carries the command's id, so a command redelivered after the
      # engine died between the append and its reply appends nothing (W13).
      #
      # @return [nil]
      def message(command, dispatcher)
        subject = subject!(command, dispatcher)
        to = command.agent.to_s.empty? ? running_on(dispatcher, command.plan) : [command.agent]
        raise Refusal, "no agent named, and none is working #{command.plan}" if to.empty?

        mailbox = Plans::Mailbox.new(dir: subject.feature.path)
        to.each do |agent|
          mailbox.append(from: "human", to: agent, body: command["text"], command: command.id)
          @run_state.hold_car("#{command.plan}/#{agent}", held: false)
        end
        nil
      end

      # HOLD, WRAP_UP or STOP into one agent's control file.
      #
      # @return [nil]
      def signal(command, dispatcher)
        dispatcher.signal(command.car, Execution::Control::WORDS.fetch(command.kind)) or
          raise Refusal, "#{command.car} is not running"
        @run_state.hold_car(command.car, held: command.kind == "hold")
        nil
      end

      # Stop All Local: every agent on this machine is told to stop, and once
      # they have gone the engine ends, and the control room with it. That is
      # the one way a run with its control room ends from the page; it never
      # ends on its own, since the page can always create more work.
      # Other machines keep running.
      #
      # @return [String]
      def stop_all(_command, dispatcher)
        Execution::Control.quit!
        count = dispatcher.running.size
        "stopping #{count} agent#{"s" unless count == 1} on #{@node.label}; " \
          "the engine and the control room shut down once they have gone"
      end

      # The model for the agent's next round on this plan (W24).
      #
      # @return [String]
      def set_model(command, dispatcher)
        id = model!(command, dispatcher)
        dispatcher.prefer_model(command.plan, command.agent, id) or
          raise Refusal, "this run's executor cannot change an agent's model"
        @run_state.choose_model(command.car, id)
        "#{command.agent} runs on #{id} from its next round"
      end

      # Compact the agent's session now (W28): it stops at its next step,
      # leaving a resume note, its session is compacted with `--resume`, and
      # it carries on in that session on the same model. Answered once the
      # continuation has started.
      #
      # @return [OpenLanes::Execution::Executor::Compaction] still at work
      # @raise [Refusal] when it cannot be compacted
      def compact(command, dispatcher)
        job = dispatcher.job(command.car) or raise Refusal, "#{command.car} is not running"
        adapter = dispatcher.adapter_for(job)
        raise Refusal, "#{adapter.name} cannot resume a session, so #{command.agent} cannot be compacted" unless adapter.compacts?
        return dispatcher.compact(command.car) if job.handle.session

        # Nothing is compacted, so the reply is a refusal, though the agent
        # still restarts in a fresh session, which is as compact as it gets.
        dispatcher.requeue(command.car)
        raise Refusal,
          "#{command.agent} has no session id yet, so it cannot be compacted: it stops at its next step " \
          "and restarts from its resume note in a fresh session"
      end

      # The model now (W27): the agent is stopped with a resume note, its
      # session compacted, and carried on in it on the new model (W28). An
      # agent whose session cannot be resumed is started again on the model
      # from its resume note instead, in a fresh session.
      #
      # @return [OpenLanes::Execution::Executor::Compaction, String]
      def switch_model(command, dispatcher)
        job = dispatcher.job(command.car) or
          raise Refusal, "#{command.car} is not running; use set_model for its next round"

        set_model(command, dispatcher)
        model = @run_state.model_for(command.car)
        adapter = dispatcher.adapter_for(job)
        return dispatcher.compact(command.car, model:) if adapter.compacts? && job.handle.session

        dispatcher.requeue(command.car)
        why = adapter.compacts? ? "it has no session id yet" : "#{adapter.name} cannot resume a session"
        "#{command.agent} stops at its next step and restarts on #{model} from its resume note " \
          "in a fresh session: #{why}"
      end

      # @return [String] the full model id
      def model!(command, dispatcher)
        subject!(command, dispatcher)
        agent = dispatcher.runner.agents.find(command.agent) or raise Refusal, "no agent called #{command.agent}"
        adapter = Adapters.for(agent.adapter)
        return command["model"] if adapter.models.empty?

        entry = adapter.model_entry(command["model"]) or raise Refusal, "#{adapter.name} offers no model #{command["model"]}"
        # What the CLI will actually be asked for, after any ceiling, so the
        # reply and the run state never name a model that will not run.
        adapter.model(entry.id)
      end

      # ---- plans ------------------------------------------------------------

      # @return [String, nil]
      def add_plan(command, dispatcher)
        ordinal = Plans::Ordinal.parse(command["ordinal"]) or raise Refusal, "#{command["ordinal"]} is not a plan number"
        subject = dispatcher.runner.tree.reload.find(ordinal) or raise Refusal, "there is no plan #{ordinal}"
        raise Refusal, "#{ordinal} is #{subject.status}, with nothing left to do" if FINISHED.include?(subject.status.key)

        claim!(ordinal)
        dispatcher.runner.add_plan(ordinal)
        dispatcher.wake!
        nil
      end

      # The idea becomes a ⚪️ plan whose spec.md opens with it, then joins the run.
      #
      # @return [String]
      def create_plans(command, dispatcher)
        tree = dispatcher.runner.tree
        idea = command["idea"]
        if (made = tree.reload.subjects.find { it.read("spec.md").to_s.include?(marker(command)) })
          return created(made.feature, dispatcher)
        end

        path = Lifecycle.create(dir: tree.dir, words: Lifecycle::Creator.topic(idea)).either(
          ->(created) { created },
          ->(problem) { raise Refusal, "could not create the plan: #{problem}" }
        )
        feature = Plans::Feature.parse(path)
        spec = Lifecycle.brief(path:, title: feature.title, root: File.dirname(tree.dir), seed: "#{idea}\n\n#{marker(command)}")
                        .write_scaffold!
        settings = idea_frontmatter(command.payload["frontmatter"])
        File.write(spec, "#{YAML.dump(settings)}---\n\n#{File.read(spec)}") unless settings.empty?
        created(feature, dispatcher)
      end

      # The idea dialog's form (W19) as spec.md frontmatter, in
      # {Plans::Spec}'s vocabulary. It used to be sent and dropped, so a plan
      # the page asked for in the quick lane at depth fast ran the full lane
      # on every agent's default model. `auto` means "let the plan decide",
      # which is what leaving the key out already says, and `research` has
      # no key in spec.md to land in, so neither is written. Anything else
      # is passed through as typed: {Plans::Spec#problems} names a bad
      # value, the way it does for one typed by hand.
      #
      # @param form [Hash, nil] `payload.frontmatter`, as the page sends it
      # @return [Hash{String => Object}] empty when there is nothing to say
      def idea_frontmatter(form)
        return {} unless form.is_a?(Hash)

        form = form.transform_keys(&:to_s)
        form.slice("lane", "frontend", "depth").each_with_object({}) do |(key, value), out|
          text = value.to_s.strip
          next if text.empty? || text == "auto"

          out[key] = key == "frontend" && %w[true false].include?(text) ? text == "true" : text
        end
      end

      # @return [String]
      def created(feature, dispatcher)
        claim!(feature.ordinal)
        dispatcher.runner.add_plan(feature.ordinal)
        dispatcher.wake!
        "created #{feature.ordinal} #{feature.slug}"
      end

      # What a file written by a command carries, so the command applied a
      # second time finds its own work and does not repeat it (W13).
      #
      # @param command [OpenLanes::Live::Command]
      # @return [String]
      def marker(command) = "<!-- cmd:#{command.id} -->"

      # @return [void]
      def claim!(ordinal)
        return if @claims.nil? || @claims.claim(ordinal)

        raise Refusal, "#{ordinal} is being worked on #{holder_label(@claims.held_by(ordinal))}"
      end

      # @param holder [String, nil] a node name
      # @return [String] `user@host` when the holder's heartbeat says
      def holder_label(holder)
        json = holder && @store.hget(@keys.nodes, holder)
        json ? JSON.parse(json).values_at("user", "host").join("@") : "another machine"
      end

      # ---- lookups ----------------------------------------------------------

      # @return [OpenLanes::Plans::Subject]
      def subject!(command, dispatcher)
        ordinal = Plans::Ordinal.parse(command.plan.to_s) or raise Refusal, "#{command.plan} is not a plan number"
        dispatcher.runner.tree.reload.find(ordinal) or raise Refusal, "there is no plan #{command.plan}"
      end

      # @return [Array<String>] agents working the plan now
      def running_on(dispatcher, plan)
        dispatcher.running.filter_map { |job| job.task.agent.name if job.key.start_with?("#{plan}/") }
      end
    end
  end
end

# frozen_string_literal: true

require "json"

module OpenLanes
  module Web
    # The demo's run, as plain snapshot hashes the shape of
    # `web/src/api/fixtures/board.json`: what {Demo} publishes, and what its
    # commands change. No plan folder is touched and no agent runs.
    #
    # Each command kind is one method, named as {Live::Commands} names its
    # handlers, raising {Refusal} with the reason the engine would give.
    #
    # The fixture carries one plan hansolo approved and one whose pull
    # request merged, each with `finished` set and no cars, so the demo
    # shows the half-height rows a real run keeps until it restarts.
    class DemoBoard
      # A command the demo will not apply.
      class Refusal < StandardError; end

      # Activity lines a running car cycles through, so the board moves.
      CHATTER = [
        "Reading the plan's work units",
        "Running the suite: 412 examples",
        "Editing lib/openlanes/web/app.rb",
        "Writing the spec for the event stream",
        "Checking rubocop: no offenses",
        "Waiting on the reviewer's mailbox"
      ].freeze

      # The one car that fans out, so the tile's extra lines can be seen and
      # tested against a real engine. Every other car keeps the fixture's none.
      FANNED = "001.00/rey-frontend"

      # Its sub-agents in flight, by name, one entry per four ticks: three,
      # then one, then none, so the cycle repeats every 12 ticks (12 seconds
      # of the demo clock).
      FAN = [%w[Explore general-purpose Plan].freeze, %w[Explore].freeze, [].freeze].freeze

      # The status a plan takes once its last question is answered.
      UNBLOCKED = { "key" => "building", "emoji" => "🟡", "label" => "Building" }.freeze

      # What each car-signal kind does to the car.
      SIGNALS = {
        "hold"    => { "held" => true },
        "wrap_up" => { "phase" => "wrap_up" },
        "compact" => { "phase" => "calm" },
        "stop"    => { "phase" => "stopped", "state" => "done" }
      }.freeze

      # The fields of a snapshot's `node` a declared identity replaces.
      IDENTITY = %w[id user host ip checkout].freeze

      # @param fixture [String] path to a `Board` JSON
      # @param random [Random]
      # @param node [OpenLanes::Live::Node, nil] a declared identity
      #   (`--identity`): this board is then that machine's, and the pretend
      #   other machine is left to the demo that has none, so two demos on
      #   one Redis never publish the same node twice
      def initialize(fixture: FIXTURE, random: Random.new(4747), node: nil)
        board = JSON.parse(File.read(fixture))
        @me = board.fetch("me")
        @others = node ? [] : board.fetch("others")
        @me["node"].merge!(node.wire(heartbeat_at: Time.now).transform_keys(&:to_s).slice(*IDENTITY)) if node
        @random = random
        @ticks = 0
      end

      # @return [Hash] this node's snapshot
      attr_reader :me

      # @return [Array<Hash>] the other nodes' snapshots
      attr_reader :others

      # One second of pretend work: tokens grow, clocks run, messages turn.
      #
      # @param now [Time]
      # @return [void]
      def advance(now)
        @ticks += 1
        [@me, *@others].each { |snapshot| advance_snapshot(snapshot, now) }
      end

      # @param command [OpenLanes::Live::Command]
      # @return [String, nil] a reason to show beside "done"
      # @raise [Refusal]
      def apply(command)
        handler = Live::Commands::HANDLERS.fetch(command.kind)
        # A kind the engine gained and the demo did not would otherwise raise
        # NoMethodError on the demo's thread, and the board would freeze.
        raise Refusal, "the demo cannot #{command.kind}" unless respond_to?(handler, true)

        send(handler, command)
      end

      private

      # @return [void]
      def advance_snapshot(snapshot, now)
        stamp = now.utc.iso8601
        snapshot["at"] = stamp
        snapshot["node"]["heartbeat_at"] = stamp
        snapshot["plans"].each { |plan| advance_plan(plan) }
        snapshot["plans"].flat_map { it["cars"] }.select { it["key"] == FANNED }.each { fan(it) }
        run = snapshot["run"]
        run["up"] = snapshot["plans"].sum { it["up"] }
        run["down"] = snapshot["plans"].sum { it["down"] }
        run["agents_working"] = running(snapshot).size
      end

      # @return [void]
      def advance_plan(plan)
        plan["cars"].select { it["state"] == "running" && !it["held"] }.each do |car|
          up = @random.rand(800..2400)
          down = @random.rand(60..240)
          car["up"] += up
          car["down"] += down
          plan["up"] += up
          plan["down"] += down
          car["elapsed"] += 1
          car["remaining"] = [car["remaining"] - 1, 0].max if car["remaining"]
          chatter(car) if (@ticks % 4).zero?
        end
        plan["elapsed"] += 1 if plan["cars"].any? { it["state"] == "running" }
      end

      # A car that stopped has nothing in flight.
      #
      # @return [void]
      def fan(car)
        car["subagents"] = car["state"] == "running" ? FAN[(@ticks / 4) % FAN.size].dup : []
      end

      # @return [void]
      def chatter(car)
        car["message"] = CHATTER[(@ticks / 4) % CHATTER.size]
        car["history"] = [car["message"], *car["history"]].first(50)
      end

      # @return [Array<Hash>] cars still at work
      def running(snapshot) = snapshot["plans"].flat_map { it["cars"] }.select { it["state"] == "running" }

      # ---- questions --------------------------------------------------------

      # @return [nil]
      def answer(command)
        plan, question = question!(command)
        plan["questions"].delete(question)
        unblock(plan) if plan["questions"].empty?
        nil
      end

      # @return [nil]
      def hold_blocked(command) = hold_question(command, true)

      # @return [nil]
      def release_hold(command) = hold_question(command, false)

      # @return [nil]
      def hold_question(command, held)
        question!(command).last["held"] = held
        nil
      end

      # @return [void]
      def unblock(plan)
        plan["status"] = UNBLOCKED.dup if %w[blocked product_blocked].include?(plan.dig("status", "key"))
        plan["cars"].each { it["state"] = "running" if it["state"] == "stuck" }
      end

      # @return [Array(Hash, Hash)] the plan and its question
      def question!(command)
        plan = plan!(command)
        number = command["question"][/\AB?(\d+)\z/i, 1] or raise Refusal, "#{command["question"]} is not a question number like B2"
        question = plan["questions"].find { it["number"] == number.to_i } or
          raise Refusal, "#{command.plan} has no open question B#{number}"
        [plan, question]
      end

      # ---- agents -----------------------------------------------------------

      # @return [String]
      def resume(command)
        plan = plan!(command)
        interrupted = plan["interrupted"] or raise Refusal, "#{command.plan} has no interrupted agent to resume"
        plan["interrupted"] = nil
        "#{interrupted["agent"]} resumes on #{command.plan} at its next turn"
      end

      # Every agent on the plan stops and the interruption is forgotten; the
      # engine also resets the worktree and sends the plan back one state,
      # which a board with no folders behind it has nothing to show for.
      #
      # @return [String]
      def discard(command)
        plan = plan!(command)
        plan["cars"].each { it.merge!(SIGNALS.fetch("stop")) }
        plan["interrupted"] = nil
        "discarded the work on #{command.plan}; its agents stopped"
      end

      # @return [nil]
      def message(command)
        plan = plan!(command)
        cars = plan["cars"].select { command.agent.to_s.empty? || it["agent"] == command.agent }
        raise Refusal, "no agent named, and none is working #{command.plan}" if cars.empty?

        cars.each do |car|
          car["history"] = ["human: #{command["text"]}", *car["history"]].first(50)
          car["held"] = false
        end
        nil
      end

      # @return [nil]
      def signal(command)
        car!(command).merge!(SIGNALS.fetch(command.kind)).tap { it["held"] = command.kind == "hold" }
        nil
      end

      # The demo has no session to compact; the car calms as a real one would
      # once its context is shed.
      #
      # @return [nil]
      def compact(command) = signal(command)

      # @return [String]
      def stop_all(_command)
        cars = running(@me)
        cars.each { it.merge!(SIGNALS.fetch("stop")) }
        @me["run"]["status"] = "quitting"
        "stopping #{cars.size} agent#{"s" unless cars.size == 1} on #{@me.dig("node", "user")}@#{@me.dig("node", "host")}"
      end

      # Queues the model for the next round and leaves the running one
      # alone, as Live::Snapshot reports it: `next_model` until a round runs
      # on it, and nil when it is the model already running.
      #
      # @return [String]
      def set_model(command) # rubocop:disable Naming/AccessorMethodName -- named for the command kind, as in Live::Commands
        car = car!(command)
        model = model!(command["model"])
        car["next_model"] = (model unless model == car["model"])
        "#{command.agent} runs on #{model} from its next round"
      end

      # @return [String]
      def switch_model(command)
        car = car!(command)
        raise Refusal, "#{command.car} is not running; use set_model for its next round" unless car["state"] == "running"

        car["model"] = model!(command["model"])
        # The switch is the model now, so nothing is queued behind it.
        car["next_model"] = nil
        "#{command.agent} compacted and carries on on #{car["model"]}"
      end

      # @return [String] the model's full id
      def model!(name)
        entry = @me["models"].find { [it["id"], it["label"]].include?(name) } or raise Refusal, "claude offers no model #{name}"
        entry["id"]
      end

      # ---- lanes (plan 020.00) ----------------------------------------------

      # `/stop NNN`: every running agent on the plan stops. The plan stays on
      # the board, stopped, so `/restart` has something to bring back.
      #
      # @return [String]
      def stop_plan(command)
        cars = plan!(command)["cars"].select { it["state"] == "running" }
        cars.each { it.merge!(SIGNALS.fetch("stop"), "held" => false) }
        "stopped #{cars.size} agent#{"s" unless cars.size == 1} on #{command.plan} and took it off the board"
      end

      # `/restart NNN`: the plan's stopped cars run again, unless one still does.
      #
      # @return [String]
      def restart_plan(command)
        plan = plan!(command)
        working = plan["cars"].select { it["state"] == "running" }.map { it["agent"] }
        raise Refusal, "#{command.plan} already has an agent: #{working.join(", ")}" unless working.empty?

        # A stuck car waits on a question, and a restart answers none.
        plan["cars"].select { it["state"] == "done" }.each { it.merge!("state" => "running", "phase" => "calm", "held" => false) }
        "#{command.plan} restarts at the next tick"
      end

      # `/concurrency N`, worded as the engine words it. Lowering it stops
      # nobody, as in the engine.
      #
      # @return [String]
      def set_concurrency(command) # rubocop:disable Naming/AccessorMethodName -- the engine's handler name
        limit = command.payload["limit"]
        raise Refusal, "concurrency must be a whole number of at least 1, not #{limit.inspect}" unless limit.is_a?(Integer) && limit >= 1

        before = @me["run"]["jobs"]
        @me["run"]["jobs"] = limit
        over = running(@me).size - limit
        wait = over.positive? ? "; the run waits for #{over} agent#{"s" unless over == 1} to finish" : ""
        "concurrency #{before} → #{limit}#{wait}"
      end

      # ---- plans ------------------------------------------------------------

      # @return [nil]
      def add_plan(command)
        ordinal = Plans::Ordinal.parse(command["ordinal"])&.to_s or raise Refusal, "#{command["ordinal"]} is not a plan number"
        entry = @me["backlog"].find { it["ordinal"] == ordinal } or raise Refusal, "there is no plan #{ordinal}"
        @me["backlog"].delete(entry)
        @me["plans"] << plan_from(entry)
        nil
      end

      # @return [String]
      def create_plans(command)
        ordinals = [*@me["plans"], *@me["backlog"]].map { it["ordinal"].to_i }
        ordinal = format("%03d.00", ordinals.max.to_i + 1)
        title = command["idea"].lines.first.to_s.strip.delete_prefix("#").strip
        @me["plans"] << plan_from({ "ordinal" => ordinal,
                                    "title" => title,
                                    "status" => { "key" => "new", "emoji" => "⚪", "label" => "New" },
                                    "lane" => "full" })
        "created #{ordinal} #{slug(title)}"
      end

      # @return [Hash] a `Plan` at its status's station, with nobody on it yet
      def plan_from(entry)
        station = @me["stations"].find { it["key"] == entry.dig("status", "key") }&.fetch("key") || @me["stations"].first["key"]
        entry.merge("slug" => slug(entry["title"]),
          "station" => station,
          "up" => 0,
          "down" => 0,
          "cost" => 0,
          "started_at" => nil,
          "elapsed" => 0,
          "cars" => [],
          "pr" => nil,
          "questions" => [],
          "interrupted" => nil,
          "claimed_by" => @me.dig("node", "id"),
          "finished" => nil)
      end

      # @return [String]
      def slug(title) = title.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")

      # ---- lookups ----------------------------------------------------------

      # @return [Hash]
      def plan!(command)
        @me["plans"].find { it["ordinal"] == command.plan } or raise Refusal, "there is no plan #{command.plan}"
      end

      # @return [Hash]
      def car!(command)
        plan!(command)["cars"].find { it["key"] == command.car } or raise Refusal, "#{command.car} is not running"
      end
    end
  end
end

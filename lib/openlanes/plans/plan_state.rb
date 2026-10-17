# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "socket"
require "time"
require "tmpdir"

module OpenLanes
  module Plans
    # `state.json` in a plan folder: what has happened to this plan, in a form
    # a program can read without parsing prose.
    #
    # Three kinds of record live here, written by three kinds of writer:
    #
    #   stages      the harness: one per agent per round, Started when it is
    #               dispatched and settled when it returns, with the adapter,
    #               model, effort, tokens and seconds it ran on
    #   signatures  the agents, through `openlanes state sign`: the ledger
    #               lines they used to append to plan.md and spec.md
    #   messages    the agents, through `openlanes mail send`: what a pair
    #               says to each other, and the RESUME notes an interrupted
    #               agent leaves for its successor
    #
    # A stage still Started whose harness process is gone is a crash, which is
    # how a restarted run finds what it has to resume.
    #
    # The folder name stays the source of truth for the plan's state; `state`
    # here is the last state the harness moved the folder to, kept so the file
    # is readable on its own.
    #
    # Every write takes a lock, re-reads, changes, and renames a temporary file
    # over the old one, so two agents signing in the same second cannot lose
    # each other's line, and a reader never sees half a file. The lock lives in
    # the system temp dir, keyed by the plan's number, because the folder it
    # protects is renamed under it as the plan moves.
    class PlanState
      FILENAME = "state.json"

      # Bumped when a field changes meaning. Readers accept older versions.
      VERSION = 1

      # Where the schema is published, so an editor can validate the file.
      SCHEMA_ID = "https://github.com/kigster/openlanes/blob/main/schemas/plan-state.schema.json"

      # The schema in this checkout.
      SCHEMA_PATH = File.expand_path("../../../schemas/plan-state.schema.json", __dir__)

      # @param dir [String] a plan folder
      # @return [OpenLanes::Plans::PlanState]
      def self.for(dir) = new(dir:)

      # @param dir [String] a plan folder
      def initialize(dir:)
        @dir = dir
      end

      # @return [String]
      attr_reader :dir

      # @return [String]
      def path = File.join(dir, FILENAME)

      # @return [Boolean]
      def exist? = File.file?(path)

      # The whole document, or a fresh one when there is none yet.
      #
      # @return [Hash]
      def read
        return skeleton unless exist?

        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        data.is_a?(Hash) ? skeleton.merge(data) : skeleton
      rescue JSON::ParserError => e
        raise Error, "#{path} is not valid JSON: #{e.message.lines.first.strip}"
      end

      # Change the document under the lock and write it back atomically.
      #
      # @yieldparam data [Hash] mutate in place
      # @return [Hash] what was written
      def update
        locked do
          data = read
          yield data
          data["plan"] = identity
          data["updated_at"] = Time.now.iso8601
          write(data)
          data
        end
      end

      # @return [Array<Hash>]
      def stages = read["stages"]

      # @return [Array<Hash>]
      def signatures = read["signatures"]

      # @return [Array<Hash>]
      def messages = read["messages"]

      # @return [String, nil]
      def state = read["state"]

      # Until when a 💣 on this plan does not halt the run: "Resume anyway
      # for 24 h" from the control room. Kept here, not in `.openlanes.yml`,
      # so it lapses on its own and nobody has to remember to take it out.
      #
      # @return [Time, nil]
      def resume_until
        text = read["resume_until"] or return nil
        parse_time(text)
      end

      # @param now [Time]
      # @return [Boolean] whether a halt on this plan is lifted right now
      def resumed?(now: Time.now) = (resume_until || now) > now

      # @param till [Time] when the halt comes back
      # @return [Time] as written
      def resume_anyway!(till:)
        update { |data| data["resume_until"] = till.iso8601 }
        till
      end

      # ---- the harness --------------------------------------------------------

      # Record or update one agent's round. A later call for the same agent
      # and round updates the latest record of it, so a round is one record
      # from dispatch to settlement.
      #
      # A new dispatch passes +reset+, which appends a record rather than
      # finding one: rounds are numbered per state and per run, so round 1 of
      # a later run shares its number with round 1 of an earlier one. Merging
      # into the earlier record would carry its session, checkout and outcome
      # into a round that has none of them yet, and replacing it would lose
      # that round from `openlanes state show`. Appending keeps both, in
      # dispatch order, which {#resumption} relies on when two rounds started
      # in the same second.
      #
      # @param agent [String]
      # @param round [Integer]
      # @param reset [Boolean] start a new record rather than update one
      # @param fields [Hash] status, started_at, finished_at, adapter, model,
      #   effort, up, down, seconds, note, to, run, session, cwd
      # @return [Hash] the stage as written
      def stage!(agent:, round:, reset: false, **fields)
        stage = nil
        update do |data|
          stage = data["stages"].rfind { |s| s["agent"] == agent && s["round"] == round } unless reset
          unless stage
            stage = { "agent" => agent, "round" => round }
            data["stages"] << stage
          end
          stage.merge!(fields.transform_keys(&:to_s).compact)
          # A settling round notes how often the plan had moved by then, in
          # the same write, so {#resumption} sees a move no stage recorded.
          stage["moves"] = data["moves"].to_i if fields.key?(:to)
        end
        stage
      end

      # Whether one agent's next round may carry on the session its last one
      # ran in (M1), and if not, why not. Asked before the new round's own
      # stage is written, so the answer is about the rounds before it.
      #
      # The latest stage of +agent+ that names a session is the candidate. It
      # is resumable only when it settled leaving the plan in +state+, no
      # stage started after it moved the plan anywhere else, and it ran in
      # +root+: `claude` keeps its sessions per working directory, so an id
      # recorded in a worktree is not found from the main checkout. The
      # candidate's own `from` is not compared, because an agent that
      # `starts_as` renames the folder on dispatch: its first round leaves
      # from Planned and works in Building, and its second leaves from
      # Building.
      #
      # A move no agent made, such as `resync dirs` or a person through
      # the CLI, records no stage, so {#state!} counts every move in `moves`
      # and a settling stage notes the count it saw: a count that has grown
      # since means the plan went away and came back. A folder renamed by
      # hand, outside openlanes, is not counted.
      #
      # A round that ends Blocked starts the next one fresh, after the
      # person answers: the plan went to Blocked and back. That is the case
      # where the earlier context would help most, and it is deliberately
      # conservative for now; the answer reaches the agent through
      # blocked.md either way.
      #
      # @param agent [String]
      # @param state [#to_s] the state key the plan is in now
      # @param root [String] the checkout the new round will run in
      # @return [OpenLanes::Plans::PlanState::Resumption]
      def resumption(agent:, state:, root:)
        data = read
        all = data["stages"]
        # `started_at` has second precision, so two rounds can tie on it; the
        # one dispatched later sits later in the array.
        last, = all.each_with_index
                   .select { |s, _| s["agent"] == agent && !s["session"].to_s.empty? }
                   .max_by { |s, i| [started(s), i] }
        return Resumption.new(session: nil, reason: "no session recorded for #{agent}") unless last

        session = last["session"]
        state = state.to_s
        reason = if last["to"].to_s.empty?
                   "round #{last["round"]} (#{session}) never settled"
                 elsif last["to"] != state
                   "the plan moved to #{last["to"]} after round #{last["round"]} (#{session})"
                 elsif (moved = moved_since(all, last, state))
                   "the plan moved to #{moved} since round #{last["round"]} (#{session})"
                 elsif last.key?("moves") && data["moves"].to_i != last["moves"]
                   "the plan moved away and back since round #{last["round"]} (#{session})"
                 elsif File.expand_path(last["cwd"].to_s) != File.expand_path(root) || last["cwd"].to_s.empty?
                   "session #{session} ran in #{last["cwd"] || "an unrecorded checkout"}, not #{root}"
                 end
        Resumption.new(session: reason ? nil : session, reason: reason || "round #{last["round"]} left it in #{state}")
      end

      # What {#resumption} decided.
      #
      # @!attribute [r] session
      #   @return [String, nil] the id to resume, nil to start fresh
      # @!attribute [r] reason
      #   @return [String] why, for the log
      Resumption = Data.define(:session, :reason) do
        # @return [Boolean]
        def resume? = !session.nil?
      end

      # @param key [Symbol, String] the state the folder was just moved to
      # @return [void]
      def state!(key)
        update do |data|
          data["moves"] = data["moves"].to_i + 1 unless data["state"] == key.to_s
          data["state"] = key.to_s
        end
      end

      # @return [Integer] how many times {#state!} has moved the plan
      def moves = read["moves"].to_i

      # Stages a dead harness left Started. Nobody is working them, and nobody
      # will finish them unless a run picks them up.
      #
      # @param alive [Proc] pid → Boolean
      # @param pid [Integer] this run, which is never its own crash
      # @return [Array<Hash>]
      def stranded(alive: method(:alive?), pid: Process.pid)
        stages.select do |s|
          run = s["run"] || {}
          s["status"] == "Started" && run["pid"] != pid && run["host"] == Socket.gethostname && !alive.call(run["pid"])
        end
      end

      # ---- the agents -------------------------------------------------------

      # One ledger line, in JSON. What `openlanes state sign` writes.
      #
      # @param agent [String]
      # @param round [Integer]
      # @param status [String] one of {Ledger::STATUSES}
      # @param note [String, nil]
      # @param next_agent [String, nil] only after Completed
      # @param at [Time]
      # @return [Hash] the signature as written
      # @raise [OpenLanes::Error] for a status outside the ledger's vocabulary,
      #   or a handoff after anything but Completed
      def sign!(agent:, round:, status:, note: nil, next_agent: nil, at: Time.now)
        raise Error, "status must be one of #{Ledger::STATUSES.join(", ")}" unless Ledger::STATUSES.include?(status)
        raise Error, "only a Completed signature may name who is next" if next_agent && status != "Completed"
        raise Error, "a signature needs an agent name" unless agent.to_s.match?(/\A[\w-]+\z/)

        signature = { "at" => at.iso8601, "agent" => agent, "status" => status, "round" => Integer(round),
                      "note" => note, "next" => next_agent }.compact
        update { |data| data["signatures"] << signature }
        signature
      end

      # Append one message and give it the next number.
      #
      # @param from [String]
      # @param to [String]
      # @param body [String]
      # @param at [Time]
      # @param after [Integer] numbers already taken elsewhere, so a plan
      #   whose older messages are in mailbox.md keeps counting from there
      # @param command [String, nil] the id of the page's command that sent
      #   it. A command is applied at least once (W13), so a second append
      #   under the same id, to the same reader, returns the first and adds
      #   nothing: an engine that died between the append and recording the
      #   reply does not say the same thing twice.
      # @return [Hash]
      def message!(from:, to:, body:, at: Time.now, after: 0, command: nil)
        message = nil
        update do |data|
          message = command && data["messages"].find { |m| m["command"] == command && m["to"] == to }
          next if message

          number = [data["messages"].map { |m| m["number"] }.max.to_i, after].max + 1
          # The id, not the number, is what a drain dedupes on: a worktree's
          # copy of this file numbers its messages independently of the main
          # checkout's, so two different messages can both be #4.
          message = { "id" => SecureRandom.uuid, "number" => number, "at" => at.iso8601, "from" => from, "to" => to,
                      "body" => body, "read" => "no" }
          message["command"] = command if command
          data["messages"] << message
        end
        message
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
      def deliver!(message, reserved: [])
        return nil if messages.any? { |m| same_message?(m, message) }

        delivered = nil
        update do |data|
          next if data["messages"].any? { |m| same_message?(m, message) }

          taken = data["messages"].map { |m| m["number"].to_i } + reserved
          number = taken.include?(message["number"]) ? taken.max + 1 : message["number"]
          # Unread whatever it arrived saying: only `mail ack` in this file
          # says its reader read it.
          delivered = message.slice("id", "number", "at", "from", "to", "body", "command")
                             .merge("number" => number, "read" => "no")
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
      # @return [Hash, nil] the message as written, nil when there is no
      #   such number
      # @raise [OpenLanes::Error] when +by+ is not the recipient
      def ack!(number, by:)
        message = nil
        update do |data|
          message = data["messages"].find { |m| m["number"] == number }
          next unless message
          raise Error, "message ##{number} is for #{message["to"]}, not #{by}" unless message["to"] == by

          message["read"] = "yes"
        end
        message
      end

      # ---- conversions ------------------------------------------------------

      # Questions the engine rewrote into lettered choices (D9), and the ones
      # it tried and could not. `blocked.md` keeps only the rewrite, so the
      # words the agent wrote live here, beside the digest that keeps a
      # restarted run from asking the model about the same text again.
      #
      # @return [Array<Hash>] oldest first; empty for a plan never converted
      def conversions = read["conversions"] || []

      # @param digest [String] SHA256 of the question's body as the agent wrote it
      # @return [Boolean] whether that text was converted, or failed to be
      def converted?(digest) = conversions.any? { it["digest"] == digest }

      # @param question [Integer] the `n` of `## Bn`
      # @param digest [String] SHA256 of +original+
      # @param original [String] the body before the rewrite
      # @param model [String] the model asked
      # @param outcome [String] "converted" or "rejected"
      # @param note [String, nil] why it was rejected
      # @param at [Time]
      # @return [Hash] the record as written
      def conversion!(question:, digest:, original:, model:, outcome:, note: nil, at: Time.now)
        record = { "question" => Integer(question), "digest" => digest, "original" => original, "at" => at.iso8601,
                   "model" => model, "outcome" => outcome, "note" => note }.compact
        update { |data| (data["conversions"] ||= []) << record }
        record
      end

      # ---- extensions -------------------------------------------------------

      # The harness asking a person for more time or another round for one
      # agent (E1), and how each request was answered. Kept here rather than
      # in the run's memory, so a grant survives a restart and an answer can
      # come from any control room, after the run that asked is gone.
      #
      # @return [Array<Hash>] oldest first; empty for a plan that never asked
      def extensions = read["extensions"] || []

      # @param agent [String]
      # @param state [String] the plan state the agent was working, a {Status} key
      # @param round [Integer]
      # @param limit [String] "time" or "rounds", whichever ran out
      # @param at [Time]
      # @return [Hash] the request as written, with its `number`
      def ask_extension!(agent:, state:, round:, limit:, at: Time.now)
        record = nil
        update do |data|
          all = (data["extensions"] ||= [])
          record = { "number" => (all.map { it["number"] }.max || 0) + 1, "agent" => agent, "state" => state.to_s,
                     "round" => Integer(round), "limit" => limit, "asked_at" => at.iso8601 }
          all << record
        end
        record
      end

      # Answer a request, or close it unanswered. Once settled it stays
      # settled: a second answer, from another page or a replayed command,
      # changes nothing.
      #
      # @param number [Integer]
      # @param fields [Hash{String => Object}] `answer`, `by`, `grant`, `seconds`, `closed`
      # @param at [Time]
      # @return [Hash, nil] the request as settled; nil when there is no such
      #   request, or when it was settled already
      def settle_extension!(number, at: Time.now, **fields)
        settled = nil
        update do |data|
          found = (data["extensions"] || []).find { it["number"] == Integer(number) } or next
          next if found.key?("settled_at")

          settled = found.merge!(fields.transform_keys(&:to_s).compact, "settled_at" => at.iso8601)
        end
        settled
      end

      # Correct how a settled request was granted, when the grant could not
      # be given as settled: time for a clock that had already stopped.
      #
      # @param number [Integer]
      # @param fields [Hash{String => Object}]
      # @return [Hash, nil] the request as it now stands
      def amend_extension!(number, **fields)
        amended = nil
        update do |data|
          amended = (data["extensions"] || []).find { it["number"] == Integer(number) }&.merge!(fields.transform_keys(&:to_s))
        end
        amended
      end

      # Mark a granted round's extra seconds as given to the round that ran on them.
      #
      # @param number [Integer]
      # @return [void]
      def spend_extension!(number)
        update { |data| (data["extensions"] || []).find { it["number"] == Integer(number) }&.store("spent", true) }
      end

      # ---- last-known-state -------------------------------------------------

      # Where the resume records live in the document.
      LAST_KNOWN = "last-known-state"

      # Keep one agent's resume record, keyed by agent, so an agent
      # interrupted in rounds 1 and 3 leaves one entry, not two nobody prunes.
      # A harness entry does not replace the agent's own of the same round or
      # later: see {LastKnownState#supersedes?}.
      #
      # @param agent [String]
      # @param entry [OpenLanes::Plans::LastKnownState]
      # @return [OpenLanes::Plans::LastKnownState] the entry kept, which is
      #   the existing one when the new one may not replace it
      # @raise [OpenLanes::Error] on an agent name that is not one token
      def record_last_known(agent, entry)
        raise Error, "a resume record needs an agent name" unless agent.to_s.match?(/\A[\w-]+\z/)

        kept = entry
        update do |data|
          section = (data[LAST_KNOWN] ||= {})
          existing = section[agent] && LastKnownState.from_h(section[agent])
          if entry.supersedes?(existing)
            section[agent] = entry.to_json_h
          else
            kept = existing
          end
        end
        kept
      end

      # @param agent [String]
      # @return [OpenLanes::Plans::LastKnownState, nil]
      def last_known(agent) = last_known_states[agent]

      # @return [Hash{String => OpenLanes::Plans::LastKnownState}] empty when
      #   no agent was ever interrupted
      def last_known_states
        (read[LAST_KNOWN] || {}).transform_values { |h| LastKnownState.from_h(h) }
      end

      # ---- memory: the agents' journals (M2) -----------------------------

      # Where the journals live in the document.
      MEMORY = "memory"

      # Append entries an agent printed to its journal for one round, in the
      # order given, numbering them after every entry the agent already has
      # in any round. Only the dispatcher calls this, under the lock every
      # write takes, so two agents printing at once cannot collide.
      #
      # @param agent [String]
      # @param round [Integer]
      # @param entries [Array<OpenLanes::Plans::Journal::Entry>]
      # @return [Array<Hash>] the entries as written, numbered
      # @raise [OpenLanes::Error] on an agent name that is not one token
      def journal!(agent:, round:, entries:)
        raise Error, "a journal needs an agent name" unless agent.to_s.match?(/\A[\w-]+\z/)
        return [] if entries.empty?

        written = []
        update do |data|
          rounds = (((data[MEMORY] ||= {})[agent] ||= {})["rounds"] ||= {})
          last = rounds.values.flatten.map { it["number"].to_i }.max || 0
          list = (rounds[Integer(round).to_s] ||= [])
          entries.each_with_index do |entry, i|
            written << entry.to_json_h(last + i + 1)
            list << written.last
          end
        end
        written
      end

      # @param agent [String]
      # @param round [Integer]
      # @return [Array<Hash>] the round's entries in order, empty when none
      def journal(agent, round) = read.dig(MEMORY, agent, "rounds", Integer(round).to_s) || []

      # The signatures as ledger entries, so the dispatcher reads them exactly
      # as it reads a line in plan.md. Each signature takes two line numbers,
      # the entry and its handoff, so {Ledger.handoff_after} pairs them.
      #
      # @return [OpenLanes::Plans::Ledger::Reading]
      def ledger
        entries = []
        handoffs = []
        signatures.each_with_index do |sig, index|
          at = parse_time(sig["at"])
          line = (index * 2) + 1
          entries << Ledger::Entry.new(at:,
            agent: sig["agent"],
            status: sig["status"],
            round: sig["round"].to_i,
            note: sig["note"],
            file: FILENAME,
            line:)
          handoffs << Ledger::Handoff.new(at:, next: sig["next"], file: FILENAME, line: line + 1) if sig["next"]
        end
        Ledger::Reading.new(entries:, handoffs:, problems: [])
      end

      private

      # @return [Hash]
      def skeleton
        { "$schema" => SCHEMA_ID, "version" => VERSION, "plan" => identity, "state" => nil,
          "updated_at" => nil, "stages" => [], "signatures" => [], "messages" => [] }
      end

      # The plan's number and slug, from the folder name it has right now.
      #
      # @return [Hash]
      def identity
        feature = Feature.parse(dir)
        feature ? { "ordinal" => feature.ordinal.to_s, "slug" => feature.slug } : { "ordinal" => nil, "slug" => File.basename(dir) }
      end

      # @param data [Hash]
      # @return [void]
      def write(data)
        tmp = "#{path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
        File.write(tmp, "#{JSON.pretty_generate(data)}\n")
        File.rename(tmp, path)
      ensure
        FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
      end

      # @return [Object] the block's value
      def locked
        lock = File.join(Dir.tmpdir, "openlanes-plan-#{lock_key}.lock")
        File.open(lock, File::RDWR | File::CREAT, 0o644) do |f|
          f.flock(File::LOCK_EX)
          yield
        end
      end

      # The plans directory and the plan's number: stable while the folder's
      # name changes underneath.
      #
      # @return [String]
      def lock_key
        plans = File.expand_path(File.dirname(dir))
        Digest::SHA256.hexdigest("#{plans}\0#{identity["ordinal"] || File.basename(dir)}")[0, 16]
      end

      # @param stage [Hash]
      # @return [Time]
      def started(stage) = parse_time(stage["started_at"])

      # @param all [Array<Hash>] every stage
      # @param since [Hash] the stage to look after
      # @param state [String]
      # @return [String, nil] a state some later stage left the plan in, other
      #   than +state+
      def moved_since(all, since, state)
        after = started(since)
        at = all.index { it.equal?(since) }
        all.each_with_index
           .select { |s, i| i > at || started(s) > after }
           .map { |s, _| s["to"].to_s }
           .find { !it.empty? && it != state }
      end

      # @param one [Hash]
      # @param other [Hash]
      # @return [Boolean] whether the two are one message, by id when both
      #   carry one, by what they say otherwise
      def same_message?(one, other)
        return one["id"] == other["id"] if one["id"] && other["id"]

        %w[from to body].all? { one[it] == other[it] } && parse_time(one["at"]) == parse_time(other["at"])
      end

      # @param text [String, nil]
      # @return [Time]
      def parse_time(text)
        Time.iso8601(text.to_s)
      rescue ArgumentError
        Time.at(0)
      end

      # @param pid [Integer, nil]
      # @return [Boolean]
      def alive?(pid)
        return false unless pid.is_a?(Integer) && pid.positive?

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end
    end
  end
end

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

      # ---- the harness --------------------------------------------------------

      # Record or update one agent's round. A second call for the same agent
      # and round updates the first, so a round is one record from dispatch
      # to settlement.
      #
      # @param agent [String]
      # @param round [Integer]
      # @param fields [Hash] status, started_at, finished_at, adapter, model,
      #   effort, up, down, seconds, note, to, run
      # @return [Hash] the stage as written
      def stage!(agent:, round:, **fields)
        stage = nil
        update do |data|
          stage = data["stages"].find { |s| s["agent"] == agent && s["round"] == round }
          unless stage
            stage = { "agent" => agent, "round" => round }
            data["stages"] << stage
          end
          stage.merge!(fields.transform_keys(&:to_s).compact)
        end
        stage
      end

      # @param key [Symbol, String] the state the folder was just moved to
      # @return [void]
      def state!(key)
        update { |data| data["state"] = key.to_s }
      end

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

# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
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
          message = { "number" => number, "at" => at.iso8601, "from" => from, "to" => to, "body" => body }
          message["command"] = command if command
          data["messages"] << message
        end
        message
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

# frozen_string_literal: true

require "fileutils"
require "json"

module OpenLanes
  module Engine
    # Where a run stands, written every second, so a harness that dies leaves
    # the next one something to restart from.
    #
    # The ledger inside each document is the record humans read and the
    # dispatcher acts on; this is the index of it, plus what the ledger cannot
    # hold: which run wrote what, process ids, tokens, and whether the run
    # that wrote a `Started` is still alive. It sits in `.plans/` rather than
    # the system temp dir because a reboot must not lose it, and it is
    # gitignored because it is about one machine's run, not the plan.
    class StateFile
      FILENAME = "openlanes-state.json"

      # Where it used to live, one directory down. Read by {#load} when the
      # current path holds nothing, so a run started under the old layout is
      # picked up rather than silently restarted from zero. Nothing writes
      # here any more and nothing deletes it: the file left behind is the
      # only record a half-finished run has.
      LEGACY_DIRNAME = "tmp"

      # The lines {.ensure_ignored!} adds. The second covers the sibling
      # {#save} writes and renames over the first — brief, but `.plans/` is a
      # directory whose other contents are committed, so a `git status` run
      # during that instant must not offer it.
      # The third is the lock an agent holds on a plan folder while it works
      # ({Plans::Lock}), which names a process on this machine and nowhere else.
      IGNORE = ["#{OpenLanes::PLANS_DIR}/#{FILENAME}", "#{OpenLanes::PLANS_DIR}/#{FILENAME}.*.tmp",
                Plans::Lock::FILENAME].freeze

      # A literal path git can be asked about for each {IGNORE} line that is
      # not one already. The temp-file glob rides with the state file.
      PROBES = { Plans::Lock::FILENAME => "#{OpenLanes::PLANS_DIR}/000.00/#{Plans::Lock::FILENAME}" }.freeze

      # @param tree [OpenLanes::Plans::Tree]
      # @return [String]
      def self.for(tree) = File.join(tree.dir, FILENAME)

      # @param tree [OpenLanes::Plans::Tree]
      # @return [String] where {LEGACY_DIRNAME} put it
      def self.legacy_for(tree) = File.join(tree.dir, LEGACY_DIRNAME, FILENAME)

      # Add the ignore lines once. Editing somebody's `.gitignore` is a thing
      # to announce, which is why this returns whether it did.
      #
      # Git answers for a literal path, and the temp-file line is a glob no
      # path equals, so it is written with the state file's line and never
      # asked about. The lock line is asked about on its own: a repository
      # that ignored the state file before locks existed still needs it.
      #
      # @param root [String] repository root
      # @return [Boolean] true when lines were added
      def self.ensure_ignored!(root)
        return false unless system("git", "-C", root, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)

        missing = []
        missing.concat(IGNORE.first(2)) unless ignored?(root, IGNORE.first)
        missing << IGNORE.last unless ignored?(root, PROBES.fetch(IGNORE.last))
        return false if missing.empty?

        path = File.join(root, ".gitignore")
        existing = File.file?(path) ? File.read(path) : ""
        glue = existing.empty? || existing.end_with?("\n") ? "" : "\n"
        File.write(path, "#{existing}#{glue}#{missing.join("\n")}\n")
        true
      end

      # @param root [String]
      # @param path [String] relative to +root+
      # @return [Boolean]
      def self.ignored?(root, path) = system("git", "-C", root, "check-ignore", "-q", path, out: File::NULL, err: File::NULL)
      private_class_method :ignored?

      # @param path [String]
      # @param pid [Integer] this run's process id
      def initialize(path:, pid: Process.pid)
        @path = path
        @pid = pid
        @data = { "run" => {}, "plans" => {} }
        @mutex = Mutex.new
      end

      # @return [String]
      attr_reader :path

      # Where a run started before the file moved up out of {LEGACY_DIRNAME}
      # would have written. {#load} falls back to it; {#save} never uses it.
      #
      # @return [String]
      def legacy_path = File.join(File.dirname(path), LEGACY_DIRNAME, File.basename(path))

      # Reads the current path, or the legacy one when the current path holds
      # nothing. A run interrupted under the old layout is otherwise invisible
      # to the run that picks it up, and {#stranded} would report no stranded
      # stages for a harness that died with several.
      #
      # @return [self]
      def load
        @mutex.synchronize do
          source = [path, legacy_path].find { |candidate| File.file?(candidate) }
          @data = JSON.parse(File.read(source)) if source
          @data = { "run" => {}, "plans" => {} } unless @data.is_a?(Hash) && @data["plans"].is_a?(Hash)
        end
        self
      rescue JSON::ParserError
        self
      end

      # Written whole to a sibling and renamed over, so a reader never sees
      # half a file.
      #
      # @return [void]
      def save
        @mutex.synchronize do
          FileUtils.mkdir_p(File.dirname(path))
          temp = "#{path}.#{@pid}.tmp"
          File.write(temp, JSON.pretty_generate(@data))
          File.rename(temp, path)
        end
      end

      # Also forgets the previous run's `waiting_on`. A live pid only says some
      # run is up, not that it watches: a plain `run`, or one with `merge.by:
      # auto`, never writes the map, so the last watch's entries would read as
      # current for as long as this run lasted.
      #
      # @param root [String]
      # @return [void]
      def begin_run!(root:)
        @mutex.synchronize do
          @data.delete("waiting_on")
          @data["run"] = { "pid" => @pid, "root" => root, "started_at" => Time.now.iso8601,
                          "heartbeat_at" => Time.now.iso8601 }
        end
      end

      # @return [void]
      def heartbeat!
        @mutex.synchronize { @data["run"]["heartbeat_at"] = Time.now.iso8601 }
      end

      # @param ordinal [String]
      # @param agent [String]
      # @param round [Integer]
      # @param fields [Hash] anything else worth keeping: status, model, file,
      #   pid, up, down, state, next, exit
      # @return [void]
      def record(ordinal, agent:, round:, **fields)
        @mutex.synchronize do
          plan = (@data["plans"][ordinal.to_s] ||= { "stages" => [] })
          stage = plan["stages"].find { |s| s["agent"] == agent && s["round"] == round }
          unless stage
            stage = { "agent" => agent, "round" => round, "run_pid" => @pid }
            plan["stages"] << stage
          end
          fields.each { |key, value| stage[key.to_s] = value }
        end
      end

      # The live run's record (W6): what a person said about the run that no
      # plan folder holds, kept here as the copy of Redis that survives Redis
      # losing it. {Live::RunRecord} writes it and reads it back on start;
      # it carries its own `seq`, so the newer of the two copies wins.
      #
      # @return [Hash, nil]
      def live = @mutex.synchronize { @data["live"]&.dup }

      # @param data [Hash] written by the next {#save}
      # @return [void]
      def live=(data)
        @mutex.synchronize { @data["live"] = data }
      end

      # The Redis outage under way (W32): when it began, when the agents were
      # paused, how many times Redis was asked since. Nil when there is none.
      #
      # @return [Hash, nil]
      def outage = @mutex.synchronize { @data["outage"]&.dup }

      # @param record [Hash, nil] written by the next {#save}
      # @return [void]
      def outage=(record)
        @mutex.synchronize { record ? @data["outage"] = record : @data.delete("outage") }
      end

      # Outages that ended, resumed or given up on, oldest first.
      #
      # @return [Array<Hash>]
      def outages = @mutex.synchronize { (@data["outages"] || []).map(&:dup) }

      # @param records [Array<Hash>]
      # @return [void]
      def outages=(records)
        @mutex.synchronize { @data["outages"] = records }
      end

      # Pull requests open and waiting on a person, by plan, as the
      # human-mode watch last saw them. Here so `openlanes list-plans`, a
      # process of its own, can say who owes what while the engine runs.
      #
      # @return [Hash{String => Array<Integer>}]
      def waiting_on = @mutex.synchronize { (@data["waiting_on"] || {}).transform_values(&:dup) }

      # @param data [Hash{String => Array<Integer>}] written by the next {#save}
      # @return [void]
      def waiting_on=(data)
        @mutex.synchronize { @data["waiting_on"] = data.transform_keys(&:to_s) }
      end

      # @param ordinal [String]
      # @return [Array<Hash>]
      def stages(ordinal) = @mutex.synchronize { (@data.dig("plans", ordinal.to_s, "stages") || []).map(&:dup) }

      # @return [Array<String>] every ordinal with a stage recorded
      def plans = @mutex.synchronize { @data["plans"].keys }

      # @return [Boolean] whether a run wrote this file and is still alive
      def running? = !@data.dig("run", "pid").nil? && !previous_run_dead?

      # @return [Boolean] whether the run that last wrote this file is gone
      def previous_run_dead?
        previous = @data.dig("run", "pid")
        return false if previous.nil? || previous == @pid

        Process.kill(0, previous)
        false
      rescue Errno::ESRCH, Errno::EPERM
        true
      end

      # Stages a dead run left `Started`. Each is an agent that was cut off
      # mid-flight and has to be re-run, with the harness's own Interrupted
      # line written so the document agrees with this file.
      #
      # @return [Array<Array(String, Hash)>] ordinal and stage
      def stranded
        return [] unless previous_run_dead?

        @mutex.synchronize do
          @data["plans"].flat_map { |ordinal, plan|
            plan["stages"].select { |s| s["status"] == "Started" && s["run_pid"] != @pid }
                          .map { |s| [ordinal, s.dup] }
          }
        end
      end
    end
  end
end

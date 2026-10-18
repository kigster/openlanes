# frozen_string_literal: true

module OpenLanes
  module Engine
    # The dispatcher's `locked-by.pid` files, counted per plan. Both halves of
    # a pair work in one folder and so share one lock file; removing it when
    # the first of them finished left the partner running in an unlocked
    # folder, which a separate `resync dirs` was then free to rename. The
    # file goes when the last job holding the plan does.
    #
    # The plan's alock (W31) follows the same count. It is taken first, by
    # {#reserve}, on the folder as it is named before the job starts: the
    # start may rename the folder, and a refusal found after the rename would
    # leave a folder renamed under somebody else's work. {#hold} moves it to
    # the new name.
    class PlanLocks
      # Raised when an agent outside openlanes holds the plan.
      class Refused < Error; end

      # @param agent_locks [AgentLocks, nil] nil leaves alock out
      def initialize(agent_locks: nil)
        @agent_locks = agent_locks
        @mutex = Mutex.new
        @held = {}
        @reserved = {}
      end

      # Take the plan's alock before its first job starts. A partner joining
      # a running plan already has it.
      #
      # @param ordinal [String]
      # @param dir [String] the plan folder, before any rename
      # @param intent [String] said to whoever reads the lock
      # @return [void]
      # @raise [Refused] when somebody else holds the folder
      def reserve(ordinal, dir, intent)
        @mutex.synchronize do
          next if @held.key?(ordinal) || @reserved.key?(ordinal) || @agent_locks.nil?
          raise Refused, "#{File.basename(dir)} is held in alock" unless @agent_locks.acquire(dir, intent)

          @reserved[ordinal] = dir
        end
      end

      # @param ordinal [String]
      # @param dir [String] the plan folder, as the job about to start sees it
      # @return [void]
      def hold(ordinal, dir)
        @mutex.synchronize do
          path, count = @held.fetch(ordinal) { [@reserved.fetch(ordinal, dir), 0] }
          # A folder renamed since the first hold carried its lock along;
          # writing at the new path again costs nothing and is never wrong.
          begin
            Plans::Lock.write(dir) if count.zero? || path != dir
          rescue Plans::Lock::Held
            drop_reservation(ordinal) if count.zero?
            raise
          end
          move_alock(path, dir) if path != dir
          @reserved.delete(ordinal)
          @held[ordinal] = [dir, count + 1]
        end
      end

      # Give back a reservation whose job never started.
      #
      # @param ordinal [String]
      # @return [void]
      def unreserve(ordinal) = @mutex.synchronize { drop_reservation(ordinal) }

      # @param ordinal [String]
      # @return [void]
      def release(ordinal)
        @mutex.synchronize do
          path, count = @held[ordinal]
          next unless path

          if count > 1
            @held[ordinal] = [path, count - 1]
          else
            @held.delete(ordinal)
            Plans::Lock.remove(path)
            @agent_locks&.release(path)
          end
        end
      end

      # @param ordinal [String]
      # @return [Integer] how many running jobs hold it
      def count(ordinal) = @mutex.synchronize { @held.fetch(ordinal, [nil, 0]).last }

      private

      # @return [void]
      def drop_reservation(ordinal)
        dir = @reserved.delete(ordinal) or return
        @agent_locks&.release(dir)
      end

      # The folder was renamed under its lock. The new name is taken before
      # the old is given back, so the plan is never left unheld; a refusal
      # here means somebody claimed a name they could only have guessed, and
      # is said rather than stopping a job that already started.
      #
      # @return [void]
      def move_alock(from, to)
        return unless @agent_locks

        UI.log("alock not moved to #{File.basename(to)}: refused", level: :warn) unless @agent_locks.acquire(to, "openlanes")
        @agent_locks.release(from)
      end
    end
  end
end

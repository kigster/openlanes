# frozen_string_literal: true

module OpenLanes
  module Engine
    # The dispatcher's `locked-by.pid` files, counted per plan. Both halves of
    # a pair work in one folder and so share one lock file; removing it when
    # the first of them finished left the partner running in an unlocked
    # folder, which a separate `resync dirs` was then free to rename. The
    # file goes when the last job holding the plan does.
    class PlanLocks
      def initialize
        @mutex = Mutex.new
        @held = {}
      end

      # @param ordinal [String]
      # @param dir [String] the plan folder, as the job about to start sees it
      # @return [void]
      def hold(ordinal, dir)
        @mutex.synchronize do
          path, count = @held.fetch(ordinal, [dir, 0])
          # A folder renamed since the first hold carried its lock along;
          # writing at the new path again costs nothing and is never wrong.
          Plans::Lock.write(dir) if count.zero? || path != dir
          @held[ordinal] = [dir, count + 1]
        end
      end

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
          end
        end
      end

      # @param ordinal [String]
      # @return [Integer] how many running jobs hold it
      def count(ordinal) = @mutex.synchronize { @held.fetch(ordinal, [nil, 0]).last }
    end
  end
end

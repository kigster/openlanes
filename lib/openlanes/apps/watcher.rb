# frozen_string_literal: true

module OpenLanes
  module Apps
    # Which processes' `restart_on` files changed since it last looked
    # (plan 012, decision 5).
    #
    # Polling, not a file-event gem: one more dependency for a check that
    # runs once a second over a handful of globs is not worth its native
    # extension, and a poll is something a spec can drive tick by tick.
    #
    # A file counts as changed when it appears, disappears, or its `mtime`
    # or size moves. Globs are Ruby's `Dir.glob`, relative to the checkout,
    # with `**/` recursive and `{a,b}` alternatives; a dotfile matches only
    # a pattern that names the dot.
    class Watcher
      # @param root [String] the checkout the globs are relative to
      # @param definition [OpenLanes::Apps::Definition]
      def initialize(root:, definition:)
        @root = root
        @watched = definition.processes.reject { it.restart_on.empty? }
        @seen = snapshot
      end

      # @return [Array<String>] names of processes with a changed file, in
      #   declared order; empty on a quiet tick
      def changed
        now = snapshot
        names = @watched.map(&:name).reject { now[it] == @seen[it] }
        @seen = now
        names
      end

      private

      # @return [Hash{String => Hash{String => Array}}] process name to path to mtime and size
      def snapshot
        @watched.to_h do |spec|
          files = Dir.glob(spec.restart_on, File::FNM_EXTGLOB, base: @root).sort.to_h do |path|
            stat = File.stat(File.join(@root, path))
            [path, [stat.mtime.to_r, stat.size]]
          rescue SystemCallError
            [path, nil]
          end
          [spec.name, files]
        end
      end
    end
  end
end

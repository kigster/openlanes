# frozen_string_literal: true

module OpenLanes
  module Memory
    # Lessons in a plain directory: the operator's own, under the XDG config
    # directory. Every way a file there can fail to be read becomes a skipped
    # lesson, never an exception, because the caller is an agent's prompt and
    # one bad file must not cost every agent its invocation.
    #
    # @!attribute [r] name
    #   @return [Symbol] the scope, `:global`
    # @!attribute [r] dir
    #   @return [String]
    Folder = Data.define(:name, :dir) do
      # @return [Array<OpenLanes::Memory::Entry, String>] a lesson file each, or why one was skipped
      def entries
        names.map { entry(File.join(dir, it)) }
      rescue SystemCallError => e
        ["#{dir}: cannot list it (#{e.class.name.split("::").last})"]
      end

      private

      # @return [Array<String>] the `.md` names, sorted so the order is the same on every machine
      def names
        return [] unless File.directory?(dir)

        Dir.children(dir).select { it.end_with?(".md") }.sort
      end

      # A symlink is refused rather than followed: dangling, it raised out of
      # prompt construction; pointing elsewhere, it put a file nobody filed as
      # a lesson into the prompt.
      #
      # @return [OpenLanes::Memory::Entry, String]
      def entry(path)
        unsafe = Lesson.unsafe_name(File.basename(path))
        return "#{path.scrub}: #{unsafe}" if unsafe

        stat = File.lstat(path)
        return "#{path}: a symlink, not a lesson file" if stat.symlink?
        return "#{path}: not a plain file" unless stat.file?

        Entry.new(path:, text: File.binread(path), cite: "`#{path}`")
      rescue SystemCallError, IOError => e
        "#{path}: cannot read it (#{e.class.name.split("::").last})"
      end
    end
  end
end

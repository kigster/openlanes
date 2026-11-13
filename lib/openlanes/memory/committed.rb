# frozen_string_literal: true

require "open3"

module OpenLanes
  module Memory
    # A project's lessons as one commit holds them, never as the working tree
    # does. Any agent with a shell can write `.openlanes/memory/lessons/` in
    # the checkout it works in; only a merged pull request moves the default
    # branch. Reading the commit is what keeps a builder's unreviewed lesson
    # out of the next reviewer's prompt (PR 196, Security Whitehat).
    #
    # @!attribute [r] name
    #   @return [Symbol] the scope, `:project`
    # @!attribute [r] root
    #   @return [String] any directory inside the repository
    # @!attribute [r] commit
    #   @return [String] the full SHA read from, fixed for the whole run
    # @!attribute [r] dir
    #   @return [String] the lessons directory, relative to the repository root
    Committed = Data.define(:name, :root, :commit, :dir) do
      # Only a plain file is a lesson: a committed symlink would be read
      # through on checkout, and a submodule is not text.
      const_set(:BLOB_MODES, %w[100644 100755].freeze)

      class << self
        # @param name [Symbol]
        # @param root [String]
        # @param ref [String] e.g. `origin/main`
        # @param dir [String]
        # @return [OpenLanes::Memory::Committed, nil] nil when +ref+ names no commit
        def at(name:, root:, ref:, dir:)
          out, status = Open3.capture2("git",
            "-C",
            root,
            "rev-parse",
            "--verify",
            "--quiet",
            "#{ref}^{commit}",
            err: File::NULL)
          new(name:, root:, commit: out.strip, dir:) if status.success? && !out.strip.empty?
        end
      end

      # @return [String] seven characters, for what a person reads
      def short = commit[0, 7]

      # @return [Array<OpenLanes::Memory::Entry, String>] a lesson file each, or why one was skipped
      def entries
        listing.filter_map { |mode, object, path| entry(mode, object, path) }
      end

      private

      # `-z` because a file name may hold a newline, and a newline in a path
      # printed into a prompt is a new prompt line.
      #
      # @return [Array<Array(String, String, String)>] mode, object, path
      def listing
        out, status = Open3.capture2("git", "-C", root, "ls-tree", "-z", commit, "--", "#{dir}/", err: File::NULL)
        return [] unless status.success?

        out.split("\0").filter_map do |line|
          meta, path = line.split("\t", 2)
          mode, _type, object = meta.split
          [mode, object, path] if path&.end_with?(".md")
        end
      end

      # @return [OpenLanes::Memory::Entry, String, nil]
      def entry(mode, object, path)
        where = "#{path} at #{short}"
        return "#{where}: not a plain file (mode #{mode})" unless self.class::BLOB_MODES.include?(mode)
        return "#{where}: the file name holds a control character" if path.match?(/[[:cntrl:]]/)

        text, status = Open3.capture2("git", "-C", root, "cat-file", "blob", object, err: File::NULL)
        return "#{where}: git could not read it" unless status.success?

        Entry.new(path: where, text:, cite: "`git show #{short}:#{path}`")
      end
    end
  end
end

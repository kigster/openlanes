# frozen_string_literal: true

module OpenLanes
  module Evals
    # What an agent changed in the repository: which paths, and how many lines.
    #
    # Computed by comparing the fixture's files with a directory, not by asking
    # git, so a recording on disk and a live checkout are measured by the same
    # code. Lines are counted as a multiset difference, added plus removed,
    # which is what a reviewer reads as the size of a diff without needing one.
    #
    # @!attribute [r] paths
    #   @return [Array<String>] relative, sorted
    # @!attribute [r] lines
    #   @return [Integer] lines added plus lines removed
    Changes = Data.define(:paths, :lines) do
      # @param glob [String]
      # @return [Array<String>] changed paths matching it
      def matching(glob) = paths.select { |p| Changes.match?(glob, p) }
    end

    class Changes
      # Never part of the diff: git's own bookkeeping and the plans, which the
      # plan-folder checks already cover.
      IGNORED = [".git", OpenLanes::PLANS_DIR].freeze

      FNMATCH = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH

      class << self
        # @param before [Hash{String => String}] the fixture's repository
        # @param dir [String] the repository afterwards
        # @return [OpenLanes::Evals::Changes]
        def between(before, dir)
          after = snapshot(dir)
          paths = (before.keys | after.keys).reject { |p| before[p] == after[p] }.sort
          lines = paths.sum { |p| line_delta(before[p].to_s, after[p].to_s) }
          new(paths:, lines:)
        end

        # @param glob [String]
        # @param path [String]
        # @return [Boolean]
        def match?(glob, path) = File.fnmatch?(glob, path, FNMATCH)

        private

        # @return [Hash{String => String}]
        def snapshot(dir)
          root = File.expand_path(dir)
          Dir.glob("**/*", File::FNM_DOTMATCH, base: root).each_with_object({}) do |rel, out|
            next if IGNORED.include?(rel.split("/").first)

            full = File.join(root, rel)
            out[rel] = File.read(full, encoding: "UTF-8") if File.file?(full)
          end
        end

        # @return [Integer]
        def line_delta(old, new)
          a = old.lines.tally
          b = new.lines.tally
          (a.keys | b.keys).sum { |line| (a.fetch(line, 0) - b.fetch(line, 0)).abs }
        end
      end
    end
  end
end

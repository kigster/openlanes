# frozen_string_literal: true

module OpenLanes
  # Where a project starts. Every command that reads or writes plans finds
  # this first and works from it, so `openlanes run` typed three directories down
  # sees the same `.plans` as it does at the top.
  #
  # The search, nearest first:
  #
  #   1. a directory holding `.openlanes.yml` or the plans directory;
  #   2. failing that, a directory holding `.git` (a directory, or the file a
  #      worktree has in its place).
  #
  # `$HOME` counts only when it holds `.openlanes.yml`. A dotfiles repository in
  # `$HOME` has a `.git` too, and taking it would make every project under it
  # that has not been initialised yet silently share one root.
  module Project
    # The project file. Its presence is what makes a directory a root even
    # where nothing else would.
    FILE = ".openlanes.yml"

    module_function

    # @param from [String] where the search starts
    # @param home [String] the one directory `.plans` and `.git` cannot claim
    # @return [String, nil] the root, or nil when nothing above +from+ is one
    def root(from: Dir.pwd, home: Dir.home)
      chain = ancestors(from)
      home = expand(home)
      chain.find { |dir| marked?(dir, home) } || chain.find { |dir| git?(dir, home) }
    end

    # Where `openlanes init` writes: the nearest repository, else +from+ itself.
    # Unlike {.root} this never looks for `.openlanes.yml` or `.plans`, because
    # it is the command that puts them there.
    #
    # @param from [String]
    # @param home [String]
    # @return [String]
    def init_root(from: Dir.pwd, home: Dir.home)
      home = expand(home)
      ancestors(from).find { |dir| git?(dir, home) } || expand(from)
    end

    # @param from [String]
    # @return [Array<String>] +from+ and every directory above it, nearest first
    def ancestors(from)
      dir = expand(from)
      chain = [dir]
      chain << (dir = File.dirname(dir)) until File.dirname(dir) == dir
      chain
    end

    # @param dir [String]
    # @param home [String]
    # @return [Boolean]
    def marked?(dir, home)
      return true if File.file?(File.join(dir, FILE))
      return false if dir == home

      File.directory?(File.join(dir, OpenLanes::PLANS_DIR))
    end

    # @param dir [String]
    # @param home [String]
    # @return [Boolean]
    def git?(dir, home) = dir != home && File.exist?(File.join(dir, ".git"))

    # Symlinks resolved, so `/tmp` and `/private/tmp` are one directory and a
    # root is compared with the working directory honestly.
    #
    # @param path [String]
    # @return [String]
    def expand(path)
      full = File.expand_path(path)
      File.exist?(full) ? File.realpath(full) : full
    end
  end
end

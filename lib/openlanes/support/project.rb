# frozen_string_literal: true

module OpenLanes
  # Where a project starts. Every command that reads or writes plans finds
  # this first and works from it, so `openlanes run` typed three directories down
  # sees the same `.plans` as it does at the top.
  #
  # The search, nearest first:
  #
  #   1. a directory holding `.openlanes/config.yml`, the legacy
  #      `.openlanes.yml`, or the plans directory;
  #   2. failing that, a directory holding `.git` (a directory, or the file a
  #      worktree has in its place).
  #
  # `$HOME` counts only when it holds a config file. A dotfiles repository in
  # `$HOME` has a `.git` too, and taking it would make every project under it
  # that has not been initialised yet silently share one root.
  module Project
    # The folder every openlanes file a project commits lives in.
    DIR = ".openlanes"

    # The project file. Its presence is what makes a directory a root even
    # where nothing else would.
    FILE = File.join(DIR, "config.yml")

    # Where the project file lived before it moved into {DIR}. Read, with a
    # notice, until a later plan removes it; the only place under `lib/` that
    # spells the old name.
    LEGACY_FILE = ".openlanes.yml"

    # What moves a project from {LEGACY_FILE} to {FILE}.
    MOVE_COMMAND = "openlanes config move"

    # `git rev-parse` asking for the directory every worktree shares.
    COMMON_DIR = %w[rev-parse --path-format=absolute --git-common-dir].freeze

    module_function

    # The project file a root actually has: {FILE} when present, else
    # {LEGACY_FILE} (with a one-line notice, once per process), else {FILE},
    # where a new one would be written.
    #
    # @param root [String] the project root
    # @return [String] an absolute path
    # @raise [OpenLanes::Error] when both files are present
    def config_path(root) = resolve(root, FILE, LEGACY_FILE)

    # One resolver for every file that moved into {DIR}, so the notice and
    # the refusal are written once.
    #
    # @param root [String]
    # @param current [String] the path relative to +root+ now
    # @param legacy [String] the path relative to +root+ before the move
    # @return [String]
    # @raise [OpenLanes::Error] when both are present
    def resolve(root, current, legacy)
      new_path = File.join(root, current)
      old_path = File.join(root, legacy)
      return new_path unless File.file?(old_path)

      if File.file?(new_path)
        raise Error, "both #{new_path} and #{old_path} exist; keep #{current} and remove #{legacy}"
      end

      notice(legacy, current)
      old_path
    end

    # Said once per process per file: a tick loop resolves the path every tick.
    #
    # @param legacy [String]
    # @param current [String]
    # @return [void]
    def notice(legacy, current)
      @noticed ||= {}
      return if @noticed[legacy]

      @noticed[legacy] = true
      UI.line("#{legacy} has moved to #{current}; run `#{MOVE_COMMAND}` to move it")
    end

    # Forget which notices were printed. For specs.
    #
    # @return [void]
    def reset_notices! = (@noticed = {})

    # @param from [String] where the search starts
    # @param home [String] the one directory `.plans` and `.git` cannot claim
    # @return [String, nil] the root, or nil when nothing above +from+ is one
    def root(from: Dir.pwd, home: Dir.home)
      chain = ancestors(from)
      home = expand(home)
      chain.find { |dir| marked?(dir, home) } || chain.find { |dir| git?(dir, home) }
    end

    # Where `openlanes init` writes: the nearest repository, else +from+ itself.
    # Unlike {.root} this never looks for a config file or `.plans`, because
    # it is the command that puts them there.
    #
    # @param from [String]
    # @param home [String]
    # @return [String]
    def init_root(from: Dir.pwd, home: Dir.home)
      home = expand(home)
      ancestors(from).find { |dir| git?(dir, home) } || expand(from)
    end

    # The repository's main checkout, the one that owns the git directory
    # every linked worktree shares (S0). The control room runs there, so a
    # settings change it commits to `main` is the one every worktree sees.
    #
    # @param dir [String] anywhere inside a checkout
    # @return [String, nil] nil outside git, or in a bare repository
    def main_checkout(dir = Dir.pwd)
      common, status = Open3.capture2("git", "-C", dir.to_s, *COMMON_DIR, err: File::NULL)
      return nil unless status.success?

      primary_of(common.chomp)
    rescue SystemCallError
      nil
    end

    # Moves the process to the main checkout when it started in a linked
    # worktree (S0), and says so on STDERR; elsewhere it stays put, silent.
    #
    # @param from [String] where the command was started
    # @return [String] the directory the process is in afterwards
    def enter_main_checkout(from = Dir.pwd)
      main = main_checkout(from)
      return from if main.nil? || expand(main) == expand(from)

      UI.line("Started in a worktree; the factory runs from the main checkout, #{main}")
      Dir.chdir(main)
      main
    end

    # The checkout a git common directory belongs to: the directory holding
    # `.git`. One definition, shared with {Lifecycle::Allocator}'s refusal.
    #
    # @param common_dir [String] `git rev-parse --git-common-dir`, absolute
    # @return [String, nil] nil for a bare repository, which has no checkout
    def primary_of(common_dir)
      return nil if common_dir.to_s.empty?
      return File.dirname(common_dir) if File.basename(common_dir) == ".git"

      nil
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
      return true if [FILE, LEGACY_FILE].any? { File.file?(File.join(dir, it)) }
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

# frozen_string_literal: true

require "fileutils"
require "open3"

# A bare `origin`, a main checkout cloned from it, and a second clone that
# stands in for everybody else merging to main. Real git throughout: the
# examples that use it are about what git does to a worktree, and a stubbed
# git would only show what the stub was told.
module OriginRepo
  # Runs git with a fixed identity, and raises with git's own words when it fails.
  #
  # @param dir [String]
  # @param args [Array<String>]
  # @return [String] stdout and stderr, stripped
  def git!(dir, *args)
    out, status = Open3.capture2e("git",
      "-C",
      dir,
      "-c",
      "user.name=Test Author",
      "-c",
      "user.email=test@example.com",
      "-c",
      "commit.gpgsign=false",
      *args)
    raise "git #{args.join(" ")} failed in #{dir}: #{out}" unless status.success?

    out.strip
  end

  # @return [String] the commit
  def commit_file(dir, name, body, message = "edit #{name}")
    path = File.join(dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    git!(dir, "add", "-A")
    git!(dir, "commit", "-q", "-m", message)
    git!(dir, "rev-parse", "HEAD")
  end

  # Turn an existing directory into the main checkout of a repository whose
  # `origin` is a bare repository beside it, and clone that origin once more
  # as the upstream others push to.
  #
  # @param main [String] the directory; created when missing
  # @param tmp [String] where origin and upstream go
  # @return [String] the upstream clone
  def publish_with_origin(main, tmp)
    origin = File.join(tmp, "origin.git")
    upstream = File.join(tmp, "upstream")
    FileUtils.mkdir_p(main)
    system("git", "init", "-q", "--bare", "--initial-branch=main", origin, out: File::NULL, err: File::NULL)
    git!(main, "init", "-q", "--initial-branch=main") unless File.directory?(File.join(main, ".git"))
    # Local config, which every worktree of the repository shares: the
    # harness's own `rebase --continue` commits as whoever this says.
    git!(main, "config", "user.name", "Test Author")
    git!(main, "config", "user.email", "test@example.com")
    git!(main, "config", "commit.gpgsign", "false")
    File.write(File.join(main, "app.rb"), "one\ntwo\nthree\n") unless File.exist?(File.join(main, "app.rb"))
    git!(main, "add", "-A")
    git!(main, "commit", "-q", "-m", "initial")
    git!(main, "remote", "add", "origin", origin)
    git!(main, "push", "-q", "-u", "origin", "main")
    system("git", "clone", "-q", origin, upstream, out: File::NULL, err: File::NULL)
    upstream
  end

  # A commit landing on origin's main from somebody else.
  #
  # @return [String] the commit
  def land(upstream, name, body)
    git!(upstream, "pull", "-q", "--rebase", "origin", "main")
    sha = commit_file(upstream, name, body, "land #{name}")
    git!(upstream, "push", "-q", "origin", "HEAD:main")
    sha
  end
end

RSpec.configure { |config| config.include OriginRepo, :origin }

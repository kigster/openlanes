# frozen_string_literal: true

require "open3"

# A real git repository around an example's `.plans`, for the examples that
# need history: a rename date, a `git mv`, a `--follow`. Never a stubbed git.
module GitRepo
  # @return [String] the repository root, the parent of `.plans`
  def repo_root = File.dirname(plans_root)

  # @param args [Array<String>]
  # @param date [String, nil] committer and author date, ISO-8601
  # @return [String] stdout
  def repo_git(*args, date: nil)
    env = date ? { "GIT_AUTHOR_DATE" => date, "GIT_COMMITTER_DATE" => date } : {}
    out, status = Open3.capture2(env,
      "git",
      "-C",
      repo_root,
      "-c",
      "user.name=Test Author",
      "-c",
      "user.email=test@example.com",
      "-c",
      "commit.gpgsign=false",
      *args,
      err: File::NULL)
    raise "git #{args.join(" ")} failed" unless status.success?

    out
  end

  # @param message [String]
  # @param date [String, nil]
  # @return [void]
  def commit_all(message, date: nil)
    repo_git("add", "-A")
    repo_git("commit", "-q", "-m", message, date:)
  end

  # @return [void]
  def init_repo = repo_git("init", "-q", "-b", "main")
end

RSpec.configure { |config| config.include GitRepo, :tree }

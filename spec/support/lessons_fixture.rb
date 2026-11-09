# frozen_string_literal: true

require "fileutils"
require "open3"

# Writes lesson files the way a person would, so the memory specs read real
# markdown off a real disk rather than a stubbed `Dir.glob`.
module LessonsFixture
  # @param dir [String]
  # @param name [String] the file name, without `.md`
  # @param meta [Hash{String => Object}] the frontmatter
  # @param body [String]
  # @return [String] the path written
  def write_lesson(dir, name, meta, body: "Why, and what to do instead.\n")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "#{name}.md")
    File.write(path, "#{YAML.dump(meta.transform_keys(&:to_s))}---\n\n#{body}")
    path
  end

  # @param id [String]
  # @return [Hash{String => Object}] a valid, active lesson, to override key by key
  def lesson_meta(id, **overrides)
    { "id" => id, "title" => "Lesson #{id}", "applies_to" => ["build"], "status" => "active" }
      .merge(overrides.transform_keys(&:to_s))
  end

  # @param path [String] a lesson file on disk
  # @param scope [Symbol]
  # @return [OpenLanes::Memory::Lesson]
  def read_lesson(path, scope: :project)
    entry = OpenLanes::Memory::Entry.new(path:, text: File.binread(path), cite: "`#{path}`")
    OpenLanes::Memory::Lesson.parse(entry, scope:)
  end

  # Makes +root+ a repository whose `origin/main` is its current commit, as
  # a clone of a project looks, without a network or a second repository.
  #
  # @param root [String]
  # @return [String] the commit `origin/main` names
  def publish_lessons(root)
    lessons_git(root, "init", "-q", "-b", "main") unless File.directory?(File.join(root, ".git"))
    lessons_git(root, "add", "-A")
    lessons_git(root, "commit", "-q", "--allow-empty", "-m", "lessons")
    lessons_git(root, "update-ref", "refs/remotes/origin/main", "HEAD")
    lessons_git(root, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
    lessons_git(root, "rev-parse", "HEAD").strip
  end

  # Who the fixture commits are from, and nothing from the developer's own config.
  LESSONS_GIT = %w[-c user.name=Test\ Author -c user.email=test@example.com -c commit.gpgsign=false
                   -c core.hooksPath=/dev/null].freeze

  # @return [String] stdout
  def lessons_git(root, *args)
    out, status = Open3.capture2("git", "-C", root, *LESSONS_GIT, *args, err: File::NULL)
    raise "git #{args.join(" ")} failed" unless status.success?

    out
  end
end

RSpec.configure { it.include LessonsFixture }

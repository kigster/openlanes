# frozen_string_literal: true

require "fileutils"

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
  # @return [Hash{String => Object}] a valid lesson, to override key by key
  def lesson_meta(id, **overrides)
    { "id" => id, "title" => "Lesson #{id}", "applies_to" => ["build"] }.merge(overrides.transform_keys(&:to_s))
  end
end

RSpec.configure { it.include LessonsFixture }

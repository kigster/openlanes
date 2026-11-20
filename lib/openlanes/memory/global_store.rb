# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module Memory
    # The operator's own store on disk, as {Mirror} writes it: active global
    # lessons in {Memory.global_dir}, candidates in its `inbox/`.
    #
    # Two runs in two projects may finish at once, so {#locked} holds an
    # exclusive `flock` on `inbox/.lock` from a sync's first read to its last
    # write, and {#write} puts every file down under a temporary name and
    # renames it into place, so a reader never sees half a lesson.
    class GlobalStore
      # The ids {#next_id} mints. A project's promotion mints `L-` ids, so a
      # global lesson cannot take one; a project lesson that reuses a `G-`
      # id on purpose still shadows it, as {Library.load} resolves ids.
      ID = /\AG-(\d{4,})\z/

      # @return [String]
      attr_reader :lessons_dir, :inbox_dir

      # @param record [OpenLanes::Memory::Candidate]
      # @return [Array<String>] the distinct projects it is tagged with
      def self.projects(record) = Array(record.meta["projects"]).grep(Hash).map { it["project"].to_s }.reject(&:empty?).uniq

      # @param lessons_dir [String] as {Memory.global_dir} names it
      # @param inbox_dir [String] as {Memory.global_inbox_dir} names it
      def initialize(lessons_dir:, inbox_dir:)
        @lessons_dir = lessons_dir
        @inbox_dir = inbox_dir
        @render = Inbox.new(dir: inbox_dir)
      end

      # The active global lessons a sync wrote. One the operator wrote by
      # hand carries no `projects:` and is left alone: a sync never edits a
      # file a person owns.
      #
      # @return [Array<OpenLanes::Memory::Candidate>]
      def mirrored = lessons.select { it.meta["status"].to_s == "active" && it.meta.key?("projects") }

      # @return [Array<OpenLanes::Memory::Candidate>] what waits for a second project
      def candidates = Inbox.new(dir: inbox_dir).candidates

      # The global ids +project+ holds its own copy of, so the read path can
      # leave them out of that project's prompt rather than say it twice.
      #
      # @param project [String]
      # @return [Array<String>]
      def held_by(project) = mirrored.select { self.class.projects(it).include?(project) }.map { it.meta["id"].to_s }

      # @return [String] one past the highest `G-` number in the global lessons
      def next_id
        taken = lessons.filter_map { it.meta["id"].to_s[ID, 1]&.to_i }
        format("G-%04d", (taken.max || 0) + 1)
      end

      # @param slug [String]
      # @return [String]
      def candidate_path(slug) = File.join(inbox_dir, "#{slug}.md")

      # @param id [String]
      # @param slug [String]
      # @return [String]
      def lesson_path(id, slug) = File.join(lessons_dir, "#{id}-#{slug}.md")

      # Written whole or not at all: the secret scan and {Lesson.parse} first,
      # as the project inbox checks, since a global lesson reaches every
      # project's prompts; then a temporary file renamed over the target.
      #
      # @param path [String]
      # @param meta [Hash{String => Object}]
      # @param body [String]
      # @return [String, nil] why it was refused; nil once written
      def write(path, meta, body)
        text = @render.render(meta, body)
        problem = problem_with(text, path)
        return problem if problem

        temporary = "#{path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
        File.write(temporary, text)
        File.rename(temporary, path)
        nil
      ensure
        FileUtils.rm_f(temporary) if temporary
      end

      # @param record [OpenLanes::Memory::Candidate, nil]
      # @return [void]
      def remove(record) = record && FileUtils.rm_f(record.path)

      # @yield with the store locked against every other process
      # @return [Object] what the block returns
      def locked
        FileUtils.mkdir_p([lessons_dir, inbox_dir])
        File.open(File.join(inbox_dir, ".lock"), File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        end
      end

      private

      # @return [Array<OpenLanes::Memory::Candidate>] every lesson file, read as the inbox reads its own
      def lessons = Inbox.new(dir: lessons_dir).candidates

      # @return [String, nil]
      def problem_with(text, path)
        found = Secrets.scan(text).map(&:kind).uniq
        return "looks like it holds #{found.join(", ")}" unless found.empty?
        return "#{path} is a symlink" if File.symlink?(path)

        Lesson.parse(Entry.new(path:, text:, cite: path), scope: :global)
        nil
      rescue Lesson::Invalid => e
        e.message.delete_prefix("#{path}: ")
      end
    end
  end
end

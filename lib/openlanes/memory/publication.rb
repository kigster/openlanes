# frozen_string_literal: true

require "open3"
require "tmpdir"

module OpenLanes
  module Memory
    # Promotion, delivered: the lessons {Promotion} settles are written into
    # a checkout of their own, cut from the default branch, and reach `main`
    # as a memory pull request that a person merges. Nothing else rides
    # along, so every change to `lessons/` is reviewed on its own.
    #
    # The finished folder is scanned once more before the commit, whole:
    # a match costs that file, is reported by kind and line, and its value
    # is printed nowhere.
    class Publication
      # What one publication did.
      #
      # @!attribute [r] branch
      #   @return [String, nil] nil when nothing was promoted
      # @!attribute [r] url
      #   @return [String, nil] the pull request; nil on a dry run or with nothing to publish
      # @!attribute [r] changes
      #   @return [Array<OpenLanes::Memory::Promotion::Change>]
      # @!attribute [r] held_back
      #   @return [Array<String>] `path: kind, line N`, one per secret found before the commit
      Result = Data.define(:branch, :url, :changes, :held_back)

      # The changes that put something in a pull request.
      LANDED = %i[promote confirm].freeze

      # @param root [String] the project root, whose inbox is promoted
      # @param publisher [#publish_memory]
      # @param base [String] the default branch the memory branch is cut from
      # @param options [Hash] `dry_run:` (true writes and opens nothing), `today:` (returns the current `Date`)
      def initialize(root:, publisher:, base:, **options)
        @root = File.expand_path(root)
        @publisher = publisher
        @base = base
        @dry_run = options.fetch(:dry_run, false)
        @today = options.fetch(:today, -> { Date.today })
      end

      # @return [OpenLanes::Memory::Publication::Result]
      def call
        return preview if @dry_run

        dir = File.join(Dir.mktmpdir("openlanes-memory"), "checkout")
        within(dir)
      ensure
        if dir
          git(@root, "worktree", "remove", "--force", dir)
          FileUtils.rm_rf(File.dirname(dir))
        end
      end

      private

      # @return [OpenLanes::Memory::Publication::Result]
      def within(dir)
        changes = promote_into(dir)
        branch = cut(dir, changes)
        return Result.new(branch: nil, url: nil, changes:, held_back: []) unless branch

        publish(dir, branch, changes)
      end

      # @return [OpenLanes::Memory::Publication::Result]
      def preview
        changes = Memory.promotion(root: @root).call(commit: false)
        Result.new(branch: nil, url: nil, changes:, held_back: [])
      end

      # A detached checkout of the default branch, then promotion with its
      # lessons written there and the candidates read from the root.
      #
      # @return [Array<OpenLanes::Memory::Promotion::Change>]
      def promote_into(dir)
        git(@root, "worktree", "add", "--detach", dir, "origin/#{@base}") || git(@root, "worktree", "add", "--detach", dir, @base) or
          raise OpenLanes::Error, "could not check out #{@base} for the memory pull request"
        changes = Promotion.new(inbox: Memory.inbox(root: @root), lessons_dir: File.join(dir, PROJECT_DIR), today: @today).call
        mirror_inbox(dir)
        changes
      end

      # The inbox travels with the lessons, so a promoted candidate leaves it
      # in the same pull request.
      #
      # @return [void]
      def mirror_inbox(dir)
        target = File.join(dir, INBOX_DIR)
        FileUtils.rm_rf(target)
        source = File.join(@root, INBOX_DIR)
        return unless File.directory?(source)

        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp_r(source, target)
      end

      # @return [String, nil] the branch, or nil when nothing landed
      def cut(dir, changes)
        landed = changes.select { LANDED.include?(it.kind) }
        return nil if landed.empty?

        branch = "memory/#{@today.call.iso8601}-#{landed.first.slug}"
        git(dir, "checkout", "-q", "-b", branch) or raise OpenLanes::Error, "could not create #{branch}"
        branch
      end

      # @return [OpenLanes::Memory::Publication::Result]
      def publish(dir, branch, changes)
        held_back = hold_back(dir)
        landed = changes.select { LANDED.include?(it.kind) && !held?(it, held_back) }
        return Result.new(branch: nil, url: nil, changes:, held_back:) if landed.empty?

        checkout = Vcs::Worktree::Checkout.new(ordinal: nil, branch:, path: dir, created: true)
        title = "Memory: #{landed.size} lesson#{"s" unless landed.size == 1}"
        url = @publisher.publish_memory(checkout:, title:, body: body(landed)).url
        Result.new(branch:, url:, changes:, held_back:)
      end

      # Every file under the checkout's `.openlanes/` that still holds a
      # secret is deleted before the commit.
      #
      # @return [Array<String>] `path: kind, line N`, relative to the checkout
      def hold_back(dir)
        Secrets.scan_tree(File.join(dir, ROOT_DIR)).flat_map do |path, findings|
          File.delete(path)
          findings.map { "#{path.delete_prefix("#{dir}/")}: #{it}" }
        end
      end

      # @return [Boolean]
      def held?(change, held_back) = change.path && held_back.any? { it.start_with?("#{change.path.split("/").last(4).join("/")}:") }

      # @return [String] the pull request body: each lesson with its evidence
      def body(landed)
        lines = landed.map { "- #{it.id} (#{it.kind}) #{it.slug}: #{it.why}" }
        <<~MARKDOWN
          Lessons promoted from the inbox by `openlanes memory promote`. A person merges this; no agent can.

          #{lines.join("\n")}
        MARKDOWN
      end

      # @return [Boolean] whether git succeeded
      def git(dir, *)
        _, status = Open3.capture2e("git", "-C", dir, "-c", "commit.gpgsign=false", *)
        status.success?
      end
    end
  end
end

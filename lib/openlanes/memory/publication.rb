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
      #   @return [Array<String>] `path: line N: kind`, one per secret found before the commit
      Result = Data.define(:branch, :url, :changes, :held_back)

      # The changes that put something in a pull request.
      LANDED = %i[promote confirm].freeze

      # @param root [String] the project root, whose inbox is promoted
      # @param publisher [#publish_memory]
      # @param base [String] the default branch the memory branch is cut from
      # @param options [Hash] `dry_run:` (true writes and opens nothing), `today:` (returns the current `Date`),
      #   `promotion:` (builds the {Promotion} from `inbox:`, `lessons_dir:` and `today:`)
      def initialize(root:, publisher:, base:, **options)
        @root = File.expand_path(root)
        @publisher = publisher
        @base = base
        @dry_run = options.fetch(:dry_run, false)
        @today = options.fetch(:today, -> { Date.today })
        @promotion = options.fetch(:promotion, Promotion.method(:new))
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

      # A detached checkout of the default branch, its inbox mirrored from
      # the root, then promotion run wholly inside it: lessons are written
      # there and promoted candidates leave the checkout's inbox, so the root
      # is not touched until the pull request is open. A push or `gh` that
      # fails takes the temporary checkout with it and leaves every
      # candidate where it was, ready for the next try.
      #
      # @return [Array<OpenLanes::Memory::Promotion::Change>]
      def promote_into(dir)
        git(@root, "worktree", "add", "--detach", dir, "origin/#{@base}") || git(@root, "worktree", "add", "--detach", dir, @base) or
          raise OpenLanes::Error, "could not check out #{@base} for the memory pull request"
        mirror_inbox(dir)
        @promotion.call(inbox: Memory.inbox(root: dir), lessons_dir: File.join(dir, PROJECT_DIR), today: @today).call
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
        held = hold_back(dir)
        landed = changes.select { LANDED.include?(it.kind) && !held.key?(it.path) }
        held_back = held.values.flatten
        return Result.new(branch: nil, url: nil, changes:, held_back:) if landed.empty?

        url = open_pull_request(dir, branch, landed, held_back)
        settle_root(landed)
        Result.new(branch:, url:, changes:, held_back:)
      end

      # @return [String, nil] the pull request's url
      def open_pull_request(dir, branch, landed, held_back)
        checkout = Vcs::Worktree::Checkout.new(ordinal: nil, branch:, path: dir, created: true)
        title = "Memory: #{landed.size} lesson#{"s" unless landed.size == 1}"
        @publisher.publish_memory(checkout:, title:, body: body(landed, held_back)).url
      end

      # The pull request is open, so the candidates it promoted leave the
      # root's inbox too; one held back stays there.
      #
      # @return [void]
      def settle_root(landed)
        inbox = Memory.inbox(root: @root)
        landed.each { inbox.remove(it.slug) }
      end

      # Every file this run wrote or changed under the checkout's
      # `.openlanes/` that holds a secret is deleted before the commit. A
      # file already on the default branch is left alone: deleting it here
      # would ride into review as a retirement nobody named, and the suite's
      # scan of the whole folder is what answers for it.
      #
      # @return [Hash{String => Array<String>}] absolute path to `path: line N: kind`, relative to the checkout
      def hold_back(dir)
        written(dir).each_with_object({}) do |path, held|
          findings = Secrets.scan(File.read(path))
          next if findings.empty?

          File.delete(path)
          held[path] = findings.map { "#{path.delete_prefix("#{dir}/")}: #{it}" }
        end
      end

      # @return [Array<String>] absolute paths of files under `.openlanes/` that differ from the default branch
      def written(dir)
        out, status = Open3.capture2e("git", "-C", dir, "status", "--porcelain", "-uall", "--", ROOT_DIR)
        return [] unless status.success?

        out.lines.map { File.join(dir, it[3..].strip) }.select { File.file?(it) }
      end

      # @return [String] the pull request body: each lesson with its evidence
      def body(landed, held_back)
        lines = landed.map { "- #{it.id} (#{it.kind}) #{it.slug}: #{it.why}" }
        held = held_back.map { "- held back, a secret was found: #{it}" }
        <<~MARKDOWN
          Lessons promoted from the inbox by `openlanes memory promote`. A person merges this; no agent can.

          #{(lines + held).join("\n")}
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

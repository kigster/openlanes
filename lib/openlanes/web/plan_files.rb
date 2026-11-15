# frozen_string_literal: true

require "digest"
require "fileutils"
require "securerandom"

module OpenLanes
  module Web
    # The plan files the page may read, and the two it may write (plan 017).
    #
    # A name is looked up in {READABLE} and never joined onto a path as typed,
    # which is what makes `../` meaningless here rather than merely refused.
    # This knows nothing of HTTP or of cars: {App} maps each refusal to a
    # status and checks the board before it calls {#write}.
    class PlanFiles
      # What the drawer lists, the lane dropdown lists and the preview reads, in the order listed.
      READABLE = %w[spec.md plan.md contract.md research.md design.md blocked.md pull-requests.md].freeze

      # What the popup may save. `blocked.md` is appended by the `answer`
      # command, and the build documents belong to the agents that own them.
      EDITABLE = %w[spec.md plan.md].freeze

      # The largest file served or saved. A plan document is prose a person
      # reads; a 60 MB `research.md` was once read whole into memory and
      # handed to the page's Markdown renderer.
      MAX_BYTES = 1024 * 1024

      # Not a readable name, not a plan, or not a file in that plan.
      class NotFound < OpenLanes::Error; end

      # A readable name the page may not write.
      class ReadOnly < OpenLanes::Error; end

      # The file changed since the page read it.
      class Stale < OpenLanes::Error; end

      # The file is larger than {MAX_BYTES}.
      class TooLarge < OpenLanes::Error; end

      # The file is not UTF-8 text, so it is not Markdown the page can show.
      class NotText < OpenLanes::Error; end

      # The body's frontmatter block is not the one on disk. Frontmatter
      # routes agents (`lane`, `frontend`, `depth`), so a crafted save must
      # not reach it even when the page would never send one.
      class FrontmatterChanged < OpenLanes::Error; end

      # One file as read.
      #
      # @!attribute body [String] the raw bytes
      # @!attribute etag [String] a strong, quoted ETag of those bytes
      Document = Data.define(:body, :etag)

      class << self
        # @param body [String]
        # @return [String] `"<sha256 hex>"`, quotes included, as HTTP sends it
        def etag(body) = %("#{Digest::SHA256.hexdigest(body.b)}")
      end

      # @param plans_dir [String] the `.plans` directory
      def initialize(plans_dir:)
        @plans_dir = plans_dir
      end

      # @param ordinal [String] a plan number, as typed in the URL
      # @return [Array<String>] readable names that exist, in {READABLE} order
      # @raise [NotFound] when the ordinal is not a plan, or its folder is gone
      def list(ordinal)
        settled(ordinal) do
          _, folder = present_folder(ordinal)
          READABLE.select { served?(folder, it) }
        end
      end

      # @param ordinal [String]
      # @param name [String]
      # @return [Document]
      # @raise [NotFound, TooLarge, NotText]
      def read(ordinal, name)
        settled(ordinal) do
          body = text(name, path_for(ordinal, name))
          Document.new(body:, etag: self.class.etag(body))
        end
      end

      # Replace a whole file, guarded three ways: an editable name, the
      # ETag the page read, and the frontmatter block unchanged.
      #
      # @param ordinal [String]
      # @param name [String]
      # @param body [String] the whole new file
      # @param if_match [String] the ETag the page read
      # @return [String] the new ETag
      # @raise [NotFound, ReadOnly, Stale, FrontmatterChanged, TooLarge, NotText]
      def write(ordinal, name, body:, if_match:)
        settled(ordinal) do
          path = path_for(ordinal, name)
          raise ReadOnly, "#{name} is read only" unless EDITABLE.include?(name)
          raise TooLarge, too_large(name, body.bytesize) if body.bytesize > MAX_BYTES

          unchanged!(name, read(ordinal, name), body, if_match)
          replace(path, body)
          self.class.etag(body)
        end
      end

      private

      # @param name [String]
      # @param current [Document] the file as it is on disk
      # @param body [String] the file as the page would save it
      # @param if_match [String] the ETag the page read
      # @return [void]
      # @raise [Stale, FrontmatterChanged]
      def unchanged!(name, current, body, if_match)
        raise Stale, "#{name} changed since it was read; reload it" unless current.etag == if_match.to_s.strip
        raise FrontmatterChanged, "the frontmatter of #{name} is locked" unless frontmatter(current.body) == frontmatter(body)
      end

      # Runs the block, and once more when the folder moved under it. A
      # transition renames the plan's folder, so a request that scanned the
      # tree a moment earlier holds a path that no longer exists: the second
      # pass scans again and finds the new name. A folder still missing then
      # is a plan that is gone, not a server error.
      #
      # @param ordinal [String]
      # @return [Object] what the block returned
      # @raise [NotFound] when the folder is missing on both passes
      def settled(ordinal)
        attempts = 0
        begin
          yield
        rescue Errno::ENOENT, Errno::ENOTDIR
          retry if (attempts += 1) < 2
          raise NotFound, "plan #{ordinal} moved while it was read; try again"
        end
      end

      # The file's text, read only once it is known to be small enough. The
      # read itself is capped too, since the file can grow between the two.
      #
      # @param name [String]
      # @param path [String]
      # @return [String] UTF-8
      # @raise [TooLarge, NotText]
      def text(name, path)
        size = File.size(path)
        raise TooLarge, too_large(name, size) if size > MAX_BYTES

        body = File.binread(path, MAX_BYTES + 1).force_encoding(Encoding::UTF_8)
        raise TooLarge, too_large(name, body.bytesize) if body.bytesize > MAX_BYTES
        raise NotText, "#{name} is not UTF-8 text, so it cannot be shown" unless body.valid_encoding? && !body.include?("\0")

        body
      end

      # @param name [String]
      # @param bytes [Integer]
      # @return [String]
      def too_large(name, bytes)
        "#{name} is #{(bytes / 1024.0).ceil} KB; files over #{MAX_BYTES / 1024} KB are not shown here"
      end

      # True for a regular file that really lives in the folder. `File.file?`
      # follows a symlink, so a `spec.md` linked to a file outside `.plans`
      # was listed and served; a link, even to a sibling, resolves elsewhere.
      #
      # @param folder [String]
      # @param name [String] a name from {READABLE}
      # @return [Boolean]
      def served?(folder, name)
        path = File.join(folder, name)
        File.file?(path) && File.realpath(path) == File.join(File.realpath(folder), name)
      end

      # The plan's folder, checked to still be there: the tree was scanned a
      # moment ago and a rename since would otherwise list as an empty plan.
      #
      # @param ordinal [String]
      # @return [Array(Plans::Ordinal, String)]
      # @raise [NotFound, Errno::ENOENT]
      def present_folder(ordinal)
        number, folder = folder_for(ordinal)
        raise Errno::ENOENT, folder unless File.directory?(folder)

        [number, folder]
      end

      # The raw frontmatter block, or nil when the file has none. Compared as
      # bytes, not as parsed YAML, so a reordered key or a changed comment is
      # a change too.
      #
      # @param content [String]
      # @return [String, nil]
      def frontmatter(content) = Frontmatter::PATTERN.match(content.b)&.then { it[1] }

      # @param path [String]
      # @param body [String]
      # @return [void]
      def replace(path, body)
        temp = File.join(File.dirname(path), ".#{File.basename(path)}.#{SecureRandom.hex(6)}.tmp")
        File.binwrite(temp, body)
        File.rename(temp, path)
      ensure
        FileUtils.rm_f(temp) if temp && File.exist?(temp)
      end

      # @param ordinal [String]
      # @param name [String]
      # @return [String]
      # @raise [NotFound]
      def path_for(ordinal, name)
        known = READABLE.find { it == name } or raise NotFound, "not a plan file: #{name}"
        number, folder = present_folder(ordinal)
        raise NotFound, "#{number} has no #{known}" unless served?(folder, known)

        File.join(folder, known)
      end

      # @param ordinal [String]
      # @return [Array(Plans::Ordinal, String)] the plan number and its folder
      # @raise [NotFound]
      def folder_for(ordinal)
        number = Plans::Ordinal.parse(ordinal.to_s) or raise NotFound, "not a plan number"
        subject = Plans.tree(@plans_dir).find(number) or raise NotFound, "there is no plan #{number}"
        [number, subject.feature.path]
      end
    end
  end
end

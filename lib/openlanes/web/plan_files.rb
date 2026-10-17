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
      # What the drawer lists and the preview reads, in the order listed.
      READABLE = %w[spec.md plan.md contract.md blocked.md research.md design.md].freeze

      # What the popup may save. `blocked.md` is appended by the `answer`
      # command, and the build documents belong to the agents that own them.
      EDITABLE = %w[spec.md plan.md].freeze

      # Not a readable name, not a plan, or not a file in that plan.
      class NotFound < OpenLanes::Error; end

      # A readable name the page may not write.
      class ReadOnly < OpenLanes::Error; end

      # The file changed since the page read it.
      class Stale < OpenLanes::Error; end

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
      # @raise [NotFound] when the ordinal is not a plan
      def list(ordinal)
        _, folder = folder_for(ordinal)
        READABLE.select { File.file?(File.join(folder, it)) }
      end

      # @param ordinal [String]
      # @param name [String]
      # @return [Document]
      # @raise [NotFound]
      def read(ordinal, name)
        body = File.binread(path_for(ordinal, name)).force_encoding(Encoding::UTF_8)
        Document.new(body:, etag: self.class.etag(body))
      end

      # Replace a whole file, guarded three ways: an editable name, the
      # ETag the page read, and the frontmatter block unchanged.
      #
      # @param ordinal [String]
      # @param name [String]
      # @param body [String] the whole new file
      # @param if_match [String] the ETag the page read
      # @return [String] the new ETag
      # @raise [NotFound, ReadOnly, Stale, FrontmatterChanged]
      def write(ordinal, name, body:, if_match:)
        path = path_for(ordinal, name)
        raise ReadOnly, "#{name} is read only" unless EDITABLE.include?(name)

        current = read(ordinal, name)
        raise Stale, "#{name} changed since it was read; reload it" unless current.etag == if_match.to_s.strip
        raise FrontmatterChanged, "the frontmatter of #{name} is locked" unless frontmatter(current.body) == frontmatter(body)

        replace(path, body)
        self.class.etag(body)
      end

      private

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
        number, folder = folder_for(ordinal)
        path = File.join(folder, known)
        raise NotFound, "#{number} has no #{known}" unless File.file?(path)

        path
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

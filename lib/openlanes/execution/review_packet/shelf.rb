# frozen_string_literal: true

require "fileutils"

module OpenLanes
  module Execution
    class ReviewPacket
      # Where built packets are kept between one reviewer's start and the
      # next: one file per plan and review round, in a directory that is this
      # user's alone.
      #
      # Every reviewer of a round reads what is kept here ahead of its own
      # instructions, so a file someone else could have written is worse than
      # no file. A packet is read back only when this user owns it and nobody
      # else can write to the directory, and nothing is kept in a directory
      # that fails the same test (PR 201, Security Whitehat). Whatever is
      # refused is only built again.
      class Shelf
        class << self
          # Outside the repository, for the reason {Executor::TRACE_DIR} is,
          # and under the operator's own state directory, not `Dir.tmpdir`.
          # On Linux that is `/tmp`, where the file name is guessable and
          # another local user could plant the next round's packet.
          #
          # @param env [Hash]
          # @return [String]
          def dir(env = ENV) = File.join(Runtime.state_home(env), "openlanes", "packets")
        end

        # @param dir [String]
        def initialize(dir: self.class.dir)
          @dir = dir
        end

        # @param name [String] the packet's file name, ending `-r<moves>.md`
        # @return [String, nil] the kept packet, nil when none can be trusted
        def read(name)
          path = File.join(@dir, name)
          stat = File.lstat(path)
          File.read(path, encoding: "UTF-8") if stat.file? && stat.owned? && private?
        rescue SystemCallError
          nil
        end

        # Written whole or not at all, and earlier rounds' packets of the
        # same plan go: nothing reads them again. A packet that cannot be
        # kept is only a round that fetches twice, so the failure is logged,
        # not raised.
        #
        # @param name [String]
        # @param text [String]
        # @return [void]
        def keep(name, text)
          FileUtils.mkdir_p(@dir, mode: 0o700)
          return UI.log("review packet not kept: #{@dir} is not a private directory of yours", level: :warn) unless private?

          path = File.join(@dir, name)
          FileUtils.rm_f(Dir.glob(path.sub(/-r\d+\.md\z/, "-r*.md")))
          File.write("#{path}.tmp", text, perm: 0o600)
          File.rename("#{path}.tmp", path)
        rescue SystemCallError => e
          UI.log("could not keep the review packet: #{e.message}", level: :warn)
        end

        private

        # @return [Boolean] ours, a real directory, and writable by nobody else
        def private?
          stat = File.lstat(@dir)
          stat.directory? && stat.owned? && stat.mode.nobits?(0o022)
        rescue SystemCallError
          false
        end
      end
    end
  end
end

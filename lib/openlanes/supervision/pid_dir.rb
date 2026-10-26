# frozen_string_literal: true

module OpenLanes
  module Supervision
    # Where the PID files of one project live (S3): `<root>/tmp/pids`, unless
    # `$OPENLANES_PID_DIR` says otherwise. An environment variable and no
    # flag, because every process has to agree on the directory, and a flag
    # is easy to give one of them and forget for the next.
    class PidDir
      # The only override.
      ENV_NAME = "OPENLANES_PID_DIR"

      # One file in the directory, and what it says; nil when it says
      # nothing readable.
      Entry = Data.define(:path, :file)

      # @param root [String] the project root
      # @param env [Hash{String => String}]
      # @return [OpenLanes::Supervision::PidDir]
      def self.for(root, env: ENV)
        override = env[ENV_NAME].to_s.strip
        new(override.empty? ? File.join(root, "tmp", "pids") : File.expand_path(override, root))
      end

      # @param path [String]
      def initialize(path)
        @path = path
      end

      # @return [String]
      attr_reader :path

      # Written whole and renamed into place, so a reader never sees half a file.
      #
      # @param file [OpenLanes::Supervision::PidFile]
      # @return [void]
      def write(file)
        FileUtils.mkdir_p(@path)
        target = File.join(@path, file.name)
        File.write("#{target}.tmp", file.to_json)
        File.rename("#{target}.tmp", target)
      end

      # @param role [String]
      # @param pid [Integer, nil] for a run, whose file name carries its pid
      # @return [OpenLanes::Supervision::PidFile, nil]
      def read(role, pid: nil) = read_path(File.join(@path, PidFile.name_for(role, pid)))

      # Removes the file only while it still names +file+'s process, so a
      # process that lost its file to a newer one cannot delete the newer one.
      #
      # @param file [OpenLanes::Supervision::PidFile]
      # @return [void]
      def remove(file)
        FileUtils.rm_f(File.join(@path, file.name)) if read(file.role, pid: file.pid)&.pid == file.pid
      end

      # @param path [String]
      # @return [void]
      def delete(path) = FileUtils.rm_f(path)

      # @return [Array<Entry>] every PID file, supervisor first, runs last
      def entries
        Dir.glob(File.join(@path, "*.pid")).map { Entry.new(path: it, file: read_path(it)) }
           .sort_by { [ORDER.index(File.basename(it.path, ".pid").sub(/-\d+\z/, "")) || ORDER.size, it.path] }
      end

      private

      # @param path [String]
      # @return [OpenLanes::Supervision::PidFile, nil]
      def read_path(path)
        PidFile.parse(File.read(path))
      rescue SystemCallError
        nil
      end
    end
  end
end

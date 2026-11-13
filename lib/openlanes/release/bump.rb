# frozen_string_literal: true

module OpenLanes
  module Release
    # Sets VERSION in one checkout, relocks, and checks the lock agrees.
    #
    # The relock is injected, so the steps around it are tested without
    # running bundler; the script's spec runs the real one.
    class Bump
      SEMVER = /\A\d+\.\d+\.\d+\z/
      REQUIRED = [VersionFile::PATH, Lockfile::PATH, "Gemfile"].freeze

      # @param root [String] the checkout to bump
      # @param relock [#call] answers whether `bundle lock` succeeded in root
      def initialize(root:, relock:)
        @root = root
        @relock = relock
      end

      # @param version [String] the new MAJOR.MINOR.PATCH
      # @param dry_run [Boolean] report the change and write nothing
      # @return [Array<String>] the lines to print
      # @raise [OpenLanes::Release::Failed] before writing anything when the
      #   input or checkout is wrong; after writing, when the relock fails or
      #   the lock still disagrees
      def call(version, dry_run: false)
        raise Failed, "#{version.inspect} is not MAJOR.MINOR.PATCH" unless version.match?(SEMVER)

        REQUIRED.each { |f| raise Failed, "#{f} not found in #{@root}" unless File.file?(path(f)) }
        source = VersionFile.new(File.read(path(VersionFile::PATH)))
        current = source.version or raise Failed, "no VERSION assignment in #{VersionFile::PATH}"

        dry_run ? preview(current, version) : apply(source, current, version)
      end

      private

      def preview(current, version)
        [
          "#{VersionFile::PATH}: #{current} -> #{version}",
          "#{Lockfile::PATH}: openlanes (#{lock.versions.join(", ")}) -> openlanes (#{version})",
          "dry run: nothing written"
        ]
      end

      def apply(source, current, version)
        File.write(path(VersionFile::PATH), source.with(version))
        raise Failed, "bundle lock failed; #{VersionFile::PATH} now says #{version}" unless @relock.call

        locked = lock.versions
        unless locked == [version]
          raise Failed, "#{Lockfile::PATH} still says openlanes (#{locked.join(", ")}), not #{version}"
        end

        ["openlanes #{current} -> #{version}: #{VersionFile::PATH} and #{Lockfile::PATH} agree"]
      end

      def lock = Lockfile.new(File.read(path(Lockfile::PATH)))

      def path(file) = File.join(@root, file)
    end
  end
end

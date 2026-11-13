# frozen_string_literal: true

module OpenLanes
  module CLI
    module Memory
      # `openlanes memory scan`
      class Scan < Base
        desc "Check that nothing under #{OpenLanes::Memory::ROOT_DIR}/ is a secret or is ignored by git. Exits 1 when something is"

        # @return [void]
        def call(**)
          lines = secrets + ignored
          return warn("#{OpenLanes::Memory::ROOT_DIR}/ is clean.") if lines.empty?

          lines.each { $stdout.puts(it) }
          refuse("#{lines.size} problem#{"s" unless lines.size == 1} to fix. What matched is not printed.", 1)
        end

        private

        # @return [Array<String>]
        def secrets
          OpenLanes::Memory.secrets(root: Dir.pwd).flat_map { |path, findings| findings.map { "#{path}: #{it}" } }
        end

        # @return [Array<String>]
        def ignored
          OpenLanes::Memory.ignored(root: Dir.pwd).map { "#{it}: ignored by git, so it is not committed with the project" }
        end
      end
    end
  end
end

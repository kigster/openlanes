# frozen_string_literal: true

module OpenLanes
  module CLI
    module App
      # `openlanes app stop` — TERM to the `openlanes app start` holding a
      # plan's ports, which stops its processes and frees them.
      class Stop < Base
        include Registry

        desc "Stop a plan's app (every app on this machine when no plan is given)"

        argument :plan, required: false, desc: "Which plan: NNN or NNN.MM"

        # @param plan [String, nil]
        # @param options [Hash]
        # @return [void]
        def call(plan: nil, **options)
          quiet?(options)
          ordinal = ordinal_of(plan)
          owners = registry.entries.values.select { ordinal.nil? || it["plan"] == ordinal }.map { it["owner"] }.uniq
          if owners.empty?
            UI.line("No app is running#{" for #{ordinal}" if ordinal} on this machine.") unless quiet?(options)
            return
          end

          owners.each { signal(it) }
        end

        private

        # @return [void]
        def signal(pid)
          Process.kill("TERM", pid)
          UI.line("Asked #{pid} to stop")
        rescue Errno::ESRCH
          UI.line("#{pid} had already stopped")
        rescue Errno::EPERM
          refuse("#{pid} is not yours to stop", 77)
        end
      end
    end
  end
end

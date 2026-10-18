# frozen_string_literal: true

module OpenLanes
  module CLI
    # `openlanes setup` — get this machine ready to run the factory: the
    # gem's `Brewfile`, then the claude CLI, `gh auth` and Redis.
    #
    # Standalone, since a machine is ready or not whichever directory it
    # was asked from.
    class Setup < Base
      standalone!
      desc "Install the tools openlanes needs (brew bundle) and check claude, gh auth and Redis"

      dry_run_option "Install nothing; list what would be installed and run the checks"
      option :redis_url, desc: "Redis to check (default: .openlanes.yml redis_url, else $REDIS_URL, else #{Live::DEFAULT_URL})"

      example [
        "      # install what is missing, then check",
        "-n    # list what would be installed, change nothing"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        quiet?(options)
        machine = machine(options)
        outcome = machine.call(dry_run: dry_run?(options))
        preview(machine, outcome) if dry_run?(options)
        $stdout.write(OpenLanes::Setup.render(outcome.checks))
        refuse("This machine is not ready: run each fix above, then openlanes setup again.", 69) unless outcome.ok?
      end

      private

      # A named seam, so a spec can stand in for brew, gh and Redis.
      #
      # @param options [Hash]
      # @return [OpenLanes::Setup::Machine]
      def machine(options) = OpenLanes::Setup.machine(redis_url: options[:redis_url])

      # @return [void]
      def preview(machine, outcome)
        install = outcome.missing.empty? ? "nothing" : outcome.missing.join(", ")
        warn("Dry run — nothing was installed.\n" \
             "Would install: #{install}\n" \
             "#{"Would run: #{machine.bundle_command.join(" ")}\n" unless outcome.missing.empty?}" \
             "Checks: #{outcome.checks.map(&:name).join(", ")}")
      end
    end
  end
end

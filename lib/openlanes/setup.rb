# frozen_string_literal: true

module OpenLanes
  # Gets a machine ready to run the factory (plan 035): the tools in the
  # gem's `Brewfile`, then what brew cannot install. `openlanes setup` and
  # `openlanes init` both come through here, so the two ask the same
  # questions of the machine and never disagree about whether it is ready.
  module Setup
    # The gem's own root, which an installed gem and a checkout both have.
    GEM_ROOT = File.expand_path("../..", __dir__)

    # The runtime tools, shipped in the gem. `Brewfile.dev` is a
    # contributor's extras and is not.
    BREWFILE = File.join(GEM_ROOT, "Brewfile")

    module_function

    # @return [OpenLanes::Setup::Machine]
    def machine(**) = Machine.new(**)

    # One line per check, ✓ or ✗, and under each ✗ the command that fixes it.
    #
    # @param checks [Array<OpenLanes::Setup::Check>]
    # @return [String]
    def render(checks)
      width = checks.map { it.name.length }.max.to_i
      checks.map do |check|
        mark = check.ok? ? UI.paint("✓", :green) : UI.paint("✗", :red)
        line = "#{mark} #{check.name.ljust(width)}  #{check.detail}".rstrip
        check.ok? || check.fix.nil? ? "#{line}\n" : "#{line}\n    fix: #{check.fix}\n"
      end.join
    end
  end
end

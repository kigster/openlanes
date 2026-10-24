# frozen_string_literal: true

module OpenLanes
  # Gets a machine ready to run the factory (plan 035): the tools in the
  # gem's `Brewfile`, then what brew cannot install. `openlanes setup` and
  # `openlanes init` both come through here, so the two ask the same
  # questions of the machine and never disagree about whether it is ready.
  #
  # It also holds what `openlanes init` settles about a project before any
  # plan exists (plan 011): its CI, who merges, and its stack.
  module Setup
    # The gem's own root, which an installed gem and a checkout both have.
    GEM_ROOT = File.expand_path("../..", __dir__)

    # The one Brewfile, shipped in the gem: the runtime tools and a
    # contributor's, which `bin/setup` bundles from the same file.
    BREWFILE = File.join(GEM_ROOT, "Brewfile")

    module_function

    # @return [OpenLanes::Setup::Machine]
    def machine(**) = Machine.new(**)

    # @return [OpenLanes::Setup::Interview]
    def interview(**) = Interview.new(**)

    # @param root [String]
    # @return [OpenLanes::Setup::StackDetector::Detection]
    def detect_stack(root) = StackDetector.new(root).call

    # @param root [String]
    # @return [Array<OpenLanes::Setup::CiDetector::Found>]
    def detect_ci(root) = CiDetector.new(root).call

    # @param env [#[]]
    # @return [OpenLanes::Setup::Extractor, nil] nil with no API key
    def extractor(env = ENV) = Extractor.from_env(env)

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

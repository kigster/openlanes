# frozen_string_literal: true

module OpenLanes
  # The agent skills that ship inside the gem, under `skills/`, and the copy
  # that puts them where a coding agent looks for them.
  module Skills
    # Where the bundled skills live: beside `agents/`, at the gem root.
    SOURCE_DIR = File.expand_path("../../skills", __dir__)

    # The shared skill store that `~/.claude/skills` and the other agents'
    # skill directories link into.
    DESTINATION = File.join(Dir.home, ".agents", "skills")

    module_function

    # @param dir [String] a directory of `<name>/SKILL.md`
    # @return [Array<OpenLanes::Skills::Skill>] by name
    def bundled(dir: SOURCE_DIR) = Skill.all(dir)

    # @param into [String]
    # @param source [String]
    # @return [OpenLanes::Skills::Installer]
    def installer(into: DESTINATION, source: SOURCE_DIR) = Installer.new(into:, skills: bundled(dir: source))
  end
end
